//  AnalyzerViewModel.swift

import Foundation
import Combine
import CoreWLAN
import AppKit
import SwiftUI
import CoreLocation

// MARK: - Enums & Settings

enum SignalDisplayMode: String, CaseIterable, Identifiable {
    case dbm = "dBm"
    case percent = "%"
    var id: String { rawValue }
}

enum NetworkRemovalInterval: TimeInterval, CaseIterable, Identifiable {
    case oneMinute = 60
    case twoMinutes = 120
    case fiveMinutes = 300
    case tenMinutes = 600
    
    var id: TimeInterval { rawValue }
    
    var title: String {
        switch self {
        case .oneMinute: return "1 min"
        case .twoMinutes: return "2 min"
        case .fiveMinutes: return "5 min"
        case .tenMinutes: return "10 min"
        }
    }
}

// Типизация ключей сортировки (вместо String)
enum SortOption: String, CaseIterable {
    case ssid, bssid, signal, channel, width, band, security, vendor, maxRate, mode, generation, firstSeen, lastSeen, wps
}

// MARK: - Models

struct ColumnDefinition: Identifiable, Codable {
    var id: String
    var title: String
    var width: CGFloat
    var isVisible: Bool
    var order: Int
    
    static let defaults: [ColumnDefinition] = [
        .init(id: SortOption.ssid.rawValue, title: "SSID", width: 160, isVisible: true, order: 0),
        .init(id: SortOption.bssid.rawValue, title: "BSSID", width: 130, isVisible: true, order: 1),
        .init(id: SortOption.signal.rawValue, title: "Signal", width: 60, isVisible: true, order: 2),
        .init(id: SortOption.channel.rawValue, title: "Ch", width: 50, isVisible: true, order: 3),
        .init(id: SortOption.channel.rawValue, title: "Ch", width: 50, isVisible: true, order: 3),
        .init(id: SortOption.width.rawValue, title: "Width", width: 60, isVisible: true, order: 4),
        .init(id: SortOption.band.rawValue, title: "Band", width: 60, isVisible: true, order: 5),
        .init(id: SortOption.security.rawValue, title: "Security", width: 110, isVisible: true, order: 6),
        .init(id: SortOption.vendor.rawValue, title: "Vendor", width: 140, isVisible: true, order: 7),
        .init(id: SortOption.maxRate.rawValue, title: "Max Rate", width: 80, isVisible: true, order: 8),
        .init(id: SortOption.generation.rawValue, title: "Gen", width: 70, isVisible: true, order: 9),
        .init(id: SortOption.mode.rawValue, title: "Mode", width: 70, isVisible: false, order: 10),
        .init(id: SortOption.firstSeen.rawValue, title: "First Seen", width: 120, isVisible: false, order: 11),
        .init(id: SortOption.lastSeen.rawValue, title: "Last Seen", width: 120, isVisible: false, order: 12),
        .init(id: SortOption.wps.rawValue, title: "WPS", width: 60, isVisible: false, order: 13)
    ]
}

// MARK: - ViewModel

// @MainActor гарантирует, что все обновления @Published идут в UI-потоке.
// Это решает проблему "Publishing changes from within view updates".
@MainActor
class AnalyzerViewModel: ObservableObject {
    
    // MARK: - Dependencies
    private let scanner = WiFiScanner() // Actor
    private let locationManager = LocationManager()
    
    // MARK: - Internal State
    private var persistentNetworks: [String: NetworkModel] = [:]
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var isScanning = false
    
    // MARK: - Color Logic
    
    /// Глобальный генератор цвета для сети, чтобы во всех графах он был одинаковым
    func colorFor(bssid: String) -> Color {
        // Используем простой хэш для детерминированного цвета
        let hash = bssid.hashValue
        // hue: 0.0 ... 1.0
        let hue = Double(abs(hash) % 1000) / 1000.0
        // Высокая яркость и насыщенность для темного фона
        return Color(hue: hue, saturation: 0.85, brightness: 1.0)
    }
    

        // MARK: - Helpers
        
        /// Конвертация dBm в проценты (0% = -100dBm, 100% = -50dBm)
        func convertToPercent(_ dbm: Int) -> Double {
            let val = Double(dbm)
            if val <= -100 { return 0 }
            if val >= -50 { return 100 }
            return (val + 100) * 2
        }
    
    // MARK: - Published Properties (UI Binding)
    @Published var networks: [NetworkModel] = []
    @Published var currentConnectedBSSID: String? = nil
    @Published var signalHistory: [String: [Int]] = [:]
    @Published var selectedBSSID: String? = nil
    
    // Settings & Filters
    @Published var filterBand24 = true { didSet { requestFilterUpdate() } }
    @Published var filterBand5 = true { didSet { requestFilterUpdate() } }
    @Published var filterBand6 = true { didSet { requestFilterUpdate() } }
    @Published var minSignalThreshold: Double = -100 { didSet { requestFilterUpdate() } }
    @Published var searchText: String = "" // Обрабатывается через debounce в init
    
    @Published var removeAfterInterval: NetworkRemovalInterval = .twoMinutes { didSet { requestFilterUpdate() } }
    @Published var signalDisplayMode: SignalDisplayMode = .dbm
    
    @Published var refreshInterval: Double = 3.0
    @Published var isSortAscending: Bool = true { didSet { applyFilters() } }
    @Published var currentSortKey: String? = SortOption.signal.rawValue { didSet { applyFilters() } }
    @Published var columnDefinitions: [ColumnDefinition] = ColumnDefinition.defaults
    
    @Published var isLocationAuthorized = false
    @Published var errorMessage: String?
    
    // MARK: - Initialization
    init() {
        setupBindings()
        loadColumnSettings()
        // Стартуем сканирование сразу, но реальные данные пойдут только после разрешения Location
        startScanningLoop()
    }
    
    private func setupBindings() {
        // Location Status Binding
        locationManager.$authorizationStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                guard let self = self else { return }
                let authorized = (status == .authorizedAlways || status == .authorized)
                self.isLocationAuthorized = authorized
                if authorized {
                    self.refresh()
                }
            }
            .store(in: &cancellables)
        
        // Search Debounce (Optimization)
        // Чтобы не пересчитывать список на каждую букву при быстром вводе
        $searchText
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.applyFilters() }
            .store(in: &cancellables)
    }
    
    // MARK: - Scanning Loop
    
    func startScanningLoop() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }
    
    func updateRefreshInterval(to newValue: Double) {
        refreshInterval = newValue
        startScanningLoop()
    }
    
    // MARK: - Refresh Logic (Async/Await)
    
    func refresh() {
        guard !isScanning else { return }
        isScanning = true
        
        let currentBSSID = CWWiFiClient.shared().interface()?.bssid()
        
        // Используем Task для вызова метода Actor-а
        Task {
            defer { isScanning = false }
            
            do {
                // Асинхронный вызов к WiFiScanner (не блокирует Main Thread)
                let scannedList = try await scanner.scan()
                
                // Следующий код выполняется автоматически на MainActor, т.к. класс помечен им
                self.errorMessage = nil
                self.currentConnectedBSSID = currentBSSID
                self.mergeNetworks(scannedList)
                
            } catch let error as WiFiError {
                // Обработка типизированных ошибок
                if case .interfaceNotFound = error {
                    self.errorMessage = "Wi-Fi is off"
                } else {
                    self.errorMessage = error.localizedDescription
                }
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }
    
    // MARK: - Data Processing
    
    private func mergeNetworks(_ newScan: [NetworkModel]) {
        let now = Date()
        
        // 1. Update Existing
        for net in newScan {
            persistentNetworks[net.bssid] = net
            updateSignalHistory(for: net)
        }
        
        // 2. Cleanup Old
        let threshold = now.addingTimeInterval(-removeAfterInterval.rawValue)
        let keysToRemove = persistentNetworks.filter { $0.value.lastSeen ?? Date.distantPast < threshold }.map { $0.key }
        
        for key in keysToRemove {
            persistentNetworks.removeValue(forKey: key)
            signalHistory.removeValue(forKey: key)
        }
        
        applyFilters()
    }
    
    private func updateSignalHistory(for net: NetworkModel) {
        // Ограничиваем историю 60 точками (например, 3 минуты при интервале 3 сек)
        var history = signalHistory[net.bssid] ?? []
        history.append(net.signal)
        if history.count > 60 {
            history.removeFirst(history.count - 60)
        }
        signalHistory[net.bssid] = history
    }
    
    // MARK: - Filtering & Sorting
    
    private func requestFilterUpdate() {
        // Простой debounce не нужен здесь, так как toggles нажимаются редко.
        // Выполняем сразу.
        applyFilters()
    }
    
    private func applyFilters() {
        let allItems = Array(persistentNetworks.values)
        let query = searchText.lowercased()
        
        // 1. Filter
        var filtered = allItems.filter { net in
            if !filterBand24 && net.band.contains("2.4") { return false }
            if !filterBand5 && net.band == "5GHz" { return false }
            if !filterBand6 && net.band == "6GHz" { return false }
            if Double(net.signal) < minSignalThreshold { return false }
            
            if !query.isEmpty {
                let matches = net.ssid.lowercased().contains(query) ||
                              net.bssid.lowercased().contains(query) ||
                              net.vendor.lowercased().contains(query)
                if !matches { return false }
            }
            return true
        }
        
        // 2. Sort
        if let keyString = currentSortKey, let key = SortOption(rawValue: keyString) {
            filtered.sort { p1, p2 in
                let result: Bool
                switch key {
                case .ssid: result = p1.ssid < p2.ssid
                case .signal: result = p1.signal < p2.signal
                case .channel: result = p1.channel < p2.channel
                case .bssid: result = p1.bssid < p2.bssid
                case .vendor: result = p1.vendor < p2.vendor
                case .security: result = p1.security < p2.security
                case .width:
                    // Сортировка по числовому значению ширины (20 < 40 < 80)
                    let w1 = Int(p1.channelWidth.filter("0123456789".contains)) ?? 0
                    let w2 = Int(p2.channelWidth.filter("0123456789".contains)) ?? 0
                    result = w1 < w2
                case .maxRate: result = p1.maxRate < p2.maxRate
                case .firstSeen: result = (p1.firstSeen ?? Date.distantPast) < (p2.firstSeen ?? Date.distantPast)
                case .lastSeen: result = (p1.lastSeen ?? Date.distantPast) < (p2.lastSeen ?? Date.distantPast)
                case .generation: result = p1.generation < p2.generation
                case .band: result = p1.band < p2.band
                default: result = p1.ssid < p2.ssid
                }
                return isSortAscending ? result : !result
            }
        }
        
        self.networks = filtered
    }
    
    // MARK: - Public Methods
    
    func sort(by key: String, ascending: Bool) {
        currentSortKey = key
        isSortAscending = ascending
        // applyFilters вызовется автоматически через didSet
    }
    
    func formatSignal(_ dbm: Int) -> String {
        switch signalDisplayMode {
        case .dbm: return "\(dbm)"
        case .percent:
            // Аппроксимация: -100dBm = 0%, -50dBm = 100%
            let quality = max(0, min(100, (dbm + 100) * 2))
            return "\(quality)%"
        }
    }
    
    // 1. Вычисляемое свойство для выбранной сети (нужно для Инспектора)
    var selectedNetwork: NetworkModel? {
        networks.first { $0.bssid == selectedBSSID }
    }

    // 2. Методы управления столбцами (нужны для ColumnSettingsView)
    func resetColumnsToDefault() {
        columnDefinitions = ColumnDefinition.defaults
        saveColumnSettings()
    }
    
    // 3. Публичные методы для геолокации (нужны для кнопок в UI)
    // Чтобы не обращаться к приватному locationManager из View
    func requestLocationAuthorization() {
        locationManager.requestAuthorization()
    }
    
    func openSystemLocationSettings() {
        locationManager.openSystemSettings()
    }
    
        // MARK: - Public System Hooks
        
        /// Вызывается из App при переходе в активное состояние,
        /// чтобы проверить, не изменил ли пользователь права доступа в Настройках
        func checkLocationAuthorization() {
            // Предполагается, что ваш класс LocationManager имеет этот метод.
            // Если это стандартный CLLocationManager, то статус обновляется автоматически через делегат,
            // но если это ваша обертка — вызываем её метод.
            locationManager.refreshAuthorizationStatus()
        }
    
    // MARK: - Export (Improved CSV)
    
    func exportCSV() {
        guard let window = NSApp.keyWindow else { return }
        
        let visibleColumns = columnDefinitions.sorted { $0.order < $1.order }.filter { $0.isVisible }
        let headers = visibleColumns.map { "\"\($0.title)\"" }.joined(separator: ",")
        
        var rows: [String] = []
        for net in networks {
            let fields = visibleColumns.map { col -> String in
                let val = getTextForExport(id: col.id, net: net)
                // Экранирование кавычек для CSV
                let escaped = val.replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escaped)\""
            }
            rows.append(fields.joined(separator: ","))
        }
        
        let csvContent = "\(headers)\n\(rows.joined(separator: "\n"))"
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.commaSeparatedText]
        savePanel.nameFieldStringValue = "WiFi_Scan_\(Int(Date().timeIntervalSince1970)).csv"
        
        savePanel.beginSheetModal(for: window) { response in
            if response == .OK, let url = savePanel.url {
                try? csvContent.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
    
    private func getTextForExport(id: String, net: NetworkModel) -> String {
        guard let option = SortOption(rawValue: id) else { return "" }
        switch option {
        case .ssid: return net.ssid
        case .bssid: return net.bssid
        case .signal: return "\(net.signal)"
        case .channel: return "\(net.channel)"
        case .width: return net.channelWidth
        case .band: return net.band
        case .security: return net.security
        case .vendor: return net.vendor
        case .maxRate: return String(format: "%.0f", net.maxRate)
        case .mode: return net.mode
        case .generation: return net.generation
        case .firstSeen: return net.firstSeen?.description ?? ""
        case .lastSeen: return net.lastSeen?.description ?? ""
        case .wps: return net.wps ?? ""
        }
    }
    
    // MARK: - Persistence
    
    func toggleColumn(_ id: String) {
        if let idx = columnDefinitions.firstIndex(where: { $0.id == id }) {
            columnDefinitions[idx].isVisible.toggle()
            saveColumnSettings()
            // Принудительно уведомляем View об изменении
            objectWillChange.send()
        }
    }
    
    func saveColumnSettings() {
        if let data = try? JSONEncoder().encode(columnDefinitions) {
            UserDefaults.standard.set(data, forKey: "WifiColumns_v2")
        }
    }
    
    private func loadColumnSettings() {
        if let data = UserDefaults.standard.data(forKey: "WifiColumns_v2"),
           let saved = try? JSONDecoder().decode([ColumnDefinition].self, from: data) {
            columnDefinitions = saved
        }
    }
}

