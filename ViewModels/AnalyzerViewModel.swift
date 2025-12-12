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
    case thirtyMinutes = 1800
    case oneHour = 3600
    case twoHours = 7200
    
    var id: TimeInterval { rawValue }
    
    var title: String {
        switch self {
        case .oneMinute: return "1 minute"
        case .twoMinutes: return "2 minutes"
        case .thirtyMinutes: return "30 minutes"
        case .oneHour: return "1 hour"
        case .twoHours: return "2 hours"
        }
    }
}

// MARK: - Models
struct ColumnDefinition: Identifiable, Codable {
    var id: String
    var title: String
    var width: CGFloat
    var isVisible: Bool
    var order: Int
    
    static let defaults: [ColumnDefinition] = [
        .init(id: "ssid", title: "SSID", width: 150, isVisible: true, order: 0),
        .init(id: "bssid", title: "BSSID", width: 120, isVisible: true, order: 1),
        .init(id: "signal", title: "Signal", width: 60, isVisible: true, order: 2),
        .init(id: "channel", title: "Channel", width: 60, isVisible: true, order: 3),
        .init(id: "width", title: "Width", width: 60, isVisible: true, order: 4),
        .init(id: "band", title: "Band", width: 60, isVisible: true, order: 5),
        .init(id: "security", title: "Security", width: 100, isVisible: true, order: 6),
        .init(id: "vendor", title: "Vendor", width: 150, isVisible: true, order: 7),
        .init(id: "maxRate", title: "Max Rate", width: 80, isVisible: true, order: 8),
        .init(id: "mode", title: "Mode", width: 80, isVisible: false, order: 9),
        .init(id: "generation", title: "Generation", width: 80, isVisible: true, order: 10),
        .init(id: "firstSeen", title: "First Seen", width: 120, isVisible: false, order: 11),
        .init(id: "lastSeen", title: "Last Seen", width: 120, isVisible: false, order: 12),
        .init(id: "wps", title: "WPS", width: 80, isVisible: false, order: 13)
    ]
}

// MARK: - ViewModel
class AnalyzerViewModel: ObservableObject {
    // MARK: - Data Source
    private let scanner = WiFiScanner()
    private var persistentNetworks: [String: NetworkModel] = [:]
    
    @Published var networks: [NetworkModel] = []
    @Published var currentConnectedBSSID: String? = nil
    @Published var signalHistory: [String: [Int]] = [:]
    @Published var selectedBSSID: String? = nil
    
    var selectedNetwork: NetworkModel? {
        networks.first { $0.bssid == selectedBSSID }
    }

    // MARK: - Settings & Filters
    @Published var filterBand24 = true { didSet { scheduleFilterUpdate() } }
    @Published var filterBand5 = true { didSet { scheduleFilterUpdate() } }
    @Published var filterBand6 = true { didSet { scheduleFilterUpdate() } }
    @Published var minSignalThreshold: Double = -100 { didSet { scheduleFilterUpdate() } }
    @Published var searchText: String = "" { didSet { scheduleFilterUpdate() } }
    
    @Published var removeAfterInterval: NetworkRemovalInterval = .twoMinutes { didSet { scheduleFilterUpdate() } }
    @Published var signalDisplayMode: SignalDisplayMode = .dbm { didSet { objectWillChange.send() } }
    
    @Published var refreshInterval: Double = 5.0
    @Published var isSortAscending: Bool = true
    @Published var currentSortKey: String? = "ssid"
    @Published var columnDefinitions: [ColumnDefinition] = ColumnDefinition.defaults
    @Published var errorMessage: String?
    @Published var isLocationAuthorized = false
    
    let locationManager = LocationManager()
    private var timer: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupLocationBinding()
        loadColumnSettings()
        startScanning()
    }
    
    private func scheduleFilterUpdate() {
        DispatchQueue.main.async { [weak self] in
            self?.applyFilters()
        }
    }
    
    // MARK: - Scanning Logic
    func refresh() {
        let currentBSSID = CWWiFiClient.shared().interface()?.bssid()
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Сканируем. Если вернется пустой массив из-за ошибки, mergeNetworks обработает это.
            let scannedList = self.scanner.scan()
            
            DispatchQueue.main.async {
                self.currentConnectedBSSID = currentBSSID
                self.mergeNetworks(scannedList)
                
                // Если сканер вернул пустоту, а права есть - возможно стоит попробовать еще раз через секунду
                if scannedList.isEmpty && self.isLocationAuthorized {
                    print("Scan returned 0 networks. Retrying might be needed.")
                }
            }
        }
    }
    
    private func mergeNetworks(_ newScan: [NetworkModel]) {
        let now = Date()
        
        // 1. Обновляем существующие
        for net in newScan {
            persistentNetworks[net.bssid] = net
            updateSignalHistory(for: net)
        }
        
        // 2. Очистка старых
        let threshold = now.addingTimeInterval(-removeAfterInterval.rawValue)
        for (bssid, net) in persistentNetworks {
            if let lastSeen = net.lastSeen, lastSeen < threshold {
                persistentNetworks.removeValue(forKey: bssid)
                signalHistory.removeValue(forKey: bssid)
            }
        }
        
        applyFilters()
    }
    
    private func updateSignalHistory(for net: NetworkModel) {
        let maxHistoryPoints = 60
        if signalHistory[net.bssid] == nil {
            signalHistory[net.bssid] = []
        }
        signalHistory[net.bssid]?.append(net.signal)
        if let count = signalHistory[net.bssid]?.count, count > maxHistoryPoints {
            signalHistory[net.bssid]?.removeFirst(count - maxHistoryPoints)
        }
    }
    
    private func applyFilters() {
        let allItems = Array(persistentNetworks.values)
        
        var filtered = allItems.filter { net in
            if !filterBand24 && (net.band.contains("2.4")) { return false }
            if !filterBand5 && (net.band.contains("5")) { return false }
            if !filterBand6 && (net.band.contains("6")) { return false }
            if Double(net.signal) < minSignalThreshold { return false }
            if !searchText.isEmpty {
                let text = searchText.lowercased()
                let matches = net.ssid.lowercased().contains(text) ||
                              net.bssid.lowercased().contains(text) ||
                              net.vendor.lowercased().contains(text)
                if !matches { return false }
            }
            return true
        }
        
        if let key = currentSortKey {
            let isAsc = isSortAscending
            filtered.sort { p1, p2 in
                switch key {
                case "ssid": return isAsc ? p1.ssid < p2.ssid : p1.ssid > p2.ssid
                case "signal": return isAsc ? p1.signal < p2.signal : p1.signal > p2.signal
                case "channel": return isAsc ? p1.channel < p2.channel : p1.channel > p2.channel
                case "bssid": return isAsc ? p1.bssid < p2.bssid : p1.bssid > p2.bssid
                case "vendor": return isAsc ? p1.vendor < p2.vendor : p1.vendor > p2.vendor
                case "security": return isAsc ? p1.security < p2.security : p1.security > p2.security
                case "width": return isAsc ? p1.channelWidth < p2.channelWidth : p1.channelWidth > p2.channelWidth
                case "firstSeen":
                    let d1 = p1.firstSeen ?? Date.distantPast
                    let d2 = p2.firstSeen ?? Date.distantPast
                    return isAsc ? d1 < d2 : d1 > d2
                case "lastSeen":
                    let d1 = p1.lastSeen ?? Date.distantPast
                    let d2 = p2.lastSeen ?? Date.distantPast
                    return isAsc ? d1 < d2 : d1 > d2
                default: return isAsc ? p1.ssid < p2.ssid : p1.ssid > p2.ssid
                }
            }
        }
        
        networks = filtered
    }
    
    // MARK: - Sorting & Config
    func updateRefreshInterval(to newValue: Double) {
        refreshInterval = newValue
        startScanning()
    }
    
    private func startScanning() {
        timer?.cancel()
        timer = Timer.publish(every: refreshInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }
    
    func sort(by key: String, ascending: Bool) {
        currentSortKey = key
        isSortAscending = ascending
        applyFilters()
    }
    
    // MARK: - Export
    func exportCSV() {
        let headers = columnDefinitions.map { $0.title }.joined(separator: ",")
        let rows = networks.map { net -> String in
            return "\(net.ssid),\(net.bssid),\(net.signal),\(net.channel),\(net.security),\(net.vendor)"
        }.joined(separator: "\n")
        
        let csvContent = "\(headers)\n\(rows)"
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.commaSeparatedText]
        savePanel.nameFieldStringValue = "WiFi_Scan_Report.csv"
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                try? csvContent.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
    
    // MARK: - Column Management
    func toggleColumn(_ id: String) {
        if let idx = columnDefinitions.firstIndex(where: { $0.id == id }) {
            columnDefinitions[idx].isVisible.toggle()
            saveColumnSettings()
            objectWillChange.send()
        }
    }
    
    func resetColumnsToDefault() {
        columnDefinitions = ColumnDefinition.defaults
        saveColumnSettings()
    }
    
    func saveColumnSettings() {
        if let data = try? JSONEncoder().encode(columnDefinitions) {
            UserDefaults.standard.set(data, forKey: "WifiColumns")
        }
    }
    
    private func loadColumnSettings() {
        if let data = UserDefaults.standard.data(forKey: "WifiColumns"),
           let saved = try? JSONDecoder().decode([ColumnDefinition].self, from: data) {
            columnDefinitions = saved
        }
    }
    
    private func setupLocationBinding() {
        locationManager.$authorizationStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.updateAuthorizationStatus(status)
            }
            .store(in: &cancellables)
    }
    
    private func updateAuthorizationStatus(_ status: CLAuthorizationStatus) {
        let isAuthorized = (status == .authorizedAlways || status == .authorized)
        self.isLocationAuthorized = isAuthorized
        
        // ИСПРАВЛЕНИЕ: Если права получены, сразу запускаем сканирование
        if isAuthorized {
            print("Location authorized! Refreshing networks...")
            startScanning() // Перезапуск таймера
            refresh()       // Немедленное обновление
        }
    }
    
    func formatSignal(_ dbm: Int) -> String {
        switch signalDisplayMode {
        case .dbm:
            return "\(dbm)"
        case .percent:
            let quality = max(0, min(100, (dbm + 100) * 2))
            return "\(quality)%"
        }
    }
}
