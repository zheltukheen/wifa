import Foundation
import Combine

struct ColumnDefinition: Identifiable {
    let id: String
    let title: String
    var isVisible: Bool
    var width: CGFloat
    var order: Int
}

@MainActor
class AnalyzerViewModel: ObservableObject {
    @Published var networks: [NetworkModel] = []
    @Published var errorMessage: String? = nil
    @Published var columnDefinitions: [ColumnDefinition] = []
    @Published var isLocationAuthorized: Bool = false
    @Published var refreshInterval: TimeInterval = 2.0
    
    // Текущее состояние сортировки (по умолчанию — по уровню сигнала по убыванию)
    @Published var currentSortKey: String? = "signal"
    @Published var isSortAscending: Bool = false
    
    private let scanner = WiFiScanner()
    let locationManager = LocationManager()
    private let defaults = UserDefaults.standard
    private var refreshTimer: Timer?
    // Следим, чтобы одновременно не выполнялось несколько сканов
    private var scanTask: Task<Void, Never>?
    
    // Конфигурация столбцов по умолчанию
    private let defaultColumnsConfig: [(id: String, title: String, isVisibleByDefault: Bool, width: CGFloat)] = [
        // Видимые по умолчанию (Network Name в самом начале)
        ("ssid", "Network Name (SSID)", true, 180.0),
        ("bssid", "BSSID", true, 150.0),
        ("band", "Band", true, 100.0),
        ("channel", "Channel", true, 80.0),
        ("channelWidth", "Channel Width", true, 120.0),
        ("generation", "Generation", true, 120.0),
        ("maxRate", "Max Rate (Mbps)", true, 120.0),
        ("mode", "Mode", true, 100.0),
        ("security", "Security", true, 120.0),
        ("seen", "Seen (s)", true, 100.0),
        ("signal", "Signal (dBm)", true, 120.0),
        ("vendor", "Vendor", true, 150.0),
        // Скрытые по умолчанию
        ("basicRates", "Basic Rates", false, 120.0),
        ("beaconInterval", "Beacon Interval", false, 120.0),
        ("centerFrequency", "Center Frequency", false, 140.0),
        ("channelUtilization", "Channel Utilization", false, 150.0),
        ("countryCode", "Country Code", false, 120.0),
        ("deviceName", "Device Name", false, 150.0),
        ("fastTransition", "Fast Transition", false, 130.0),
        ("firstSeen", "First Seen", false, 150.0),
        ("lastSeen", "Last Seen", false, 150.0),
        ("minRate", "Min Rate", false, 120.0),
        ("noise", "Noise (dBm)", false, 120.0),
        ("protectionMode", "Protection Mode", false, 140.0),
        ("snr", "SNR", false, 100.0),
        ("stations", "Stations", false, 100.0),
        ("streams", "Streams", false, 100.0),
        ("type", "Type", false, 100.0),
        ("wps", "WPS", false, 120.0)
    ]
    
    init() {
        setupColumns()
        setupLocationManager()
        loadRefreshInterval()
        startRefreshTimerIfAuthorized()
        refresh()
    }
    
    private func setupLocationManager() {
        locationManager.onAuthorizationChanged = { [weak self] (authorized: Bool) in
            Task { @MainActor in
                guard let self else { return }
                self.isLocationAuthorized = authorized
                if authorized {
                    self.errorMessage = nil
                    self.startRefreshTimerIfAuthorized()
                    self.refresh()
                } else {
                    self.refreshTimer?.invalidate()
                    self.errorMessage = "Для отображения SSID и BSSID требуется разрешение Location Services. Пожалуйста, включите его в System Settings → Privacy & Security → Location Services."
                }
            }
        }
        locationManager.requestAuthorization()
        isLocationAuthorized = locationManager.isAuthorized
    }
    
    private func setupColumns(useSavedSettings: Bool = true) {
        // Загружаем сохраненные настройки (если нужно)
        let savedOrder: [String]
        let savedVisibility: [String: Bool]
        let savedWidths: [String: Double]
        
        if useSavedSettings {
            savedOrder = defaults.array(forKey: "ColumnOrder") as? [String] ?? []
            savedVisibility = defaults.dictionary(forKey: "ColumnVisibility") as? [String: Bool] ?? [:]
            savedWidths = defaults.dictionary(forKey: "ColumnWidths") as? [String: Double] ?? [:]
        } else {
            savedOrder = []
            savedVisibility = [:]
            savedWidths = [:]
        }
        
        columnDefinitions = defaultColumnsConfig.enumerated().map { index, col in
            let (id, title, defaultVisible, defaultWidth) = col
            let order = savedOrder.firstIndex(of: id) ?? index
            let isVisible = savedVisibility[id] ?? defaultVisible
            let width = CGFloat(savedWidths[id] ?? Double(defaultWidth))
            
            return ColumnDefinition(
                id: id,
                title: title,
                isVisible: isVisible,
                width: width,
                order: order
            )
        }.sorted { $0.order < $1.order }
    }
    
    func saveColumnSettings() {
        defaults.set(columnDefinitions.map { $0.id }, forKey: "ColumnOrder")
        defaults.set(Dictionary(uniqueKeysWithValues: columnDefinitions.map { ($0.id, $0.isVisible) }), forKey: "ColumnVisibility")
        defaults.set(Dictionary(uniqueKeysWithValues: columnDefinitions.map { ($0.id, $0.width) }), forKey: "ColumnWidths")
    }
    
    func resetColumnsToDefault() {
        // Удаляем сохранённые настройки и пересоздаём столбцы по умолчанию
        defaults.removeObject(forKey: "ColumnOrder")
        defaults.removeObject(forKey: "ColumnVisibility")
        defaults.removeObject(forKey: "ColumnWidths")
        setupColumns(useSavedSettings: false)
        saveColumnSettings()
    }
    
    func toggleColumn(_ id: String) {
        if let index = columnDefinitions.firstIndex(where: { $0.id == id }) {
            columnDefinitions[index].isVisible.toggle()
            saveColumnSettings()
        }
    }
    
    private func loadRefreshInterval() {
        let saved = defaults.double(forKey: "RefreshIntervalSeconds")
        if saved > 0 {
            refreshInterval = saved
        } else {
            refreshInterval = 2.0
        }
    }
    
    private func startRefreshTimerIfAuthorized() {
        refreshTimer?.invalidate()
        guard isLocationAuthorized, refreshInterval > 0 else { return }
        
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.refresh()
            }
        }
    }
    
    func updateRefreshInterval(to seconds: TimeInterval) {
        refreshInterval = seconds
        defaults.set(seconds, forKey: "RefreshIntervalSeconds")
        startRefreshTimerIfAuthorized()
    }
    
    func refresh() {
        guard isLocationAuthorized else {
            locationManager.requestAuthorization()
            return
        }
        
        // Не запускаем новый скан, если предыдущий ещё идёт
        if let task = scanTask, !task.isCancelled {
            return
        }
        
        let scannerRef = self.scanner
        scanTask = Task.detached(priority: .background) { [weak self] in
            let nets = scannerRef.scan()
            await MainActor.run {
                guard let self else { return }
                self.networks = nets
                if let key = self.currentSortKey {
                    self.sort(by: key, ascending: self.isSortAscending)
                }
                if nets.isEmpty {
                    self.errorMessage = "Не удалось найти Wi-Fi сети. Проверьте, что Wi-Fi включен и Location Services разрешены."
                } else {
                    self.errorMessage = nil
                }
                // Сброс указателя на задачу после завершения
                self.scanTask = nil
            }
        }
    }
    
    func sort(by key: String, ascending: Bool) {
        currentSortKey = key
        isSortAscending = ascending
        networks.sort { a, b in
            // Для убывающей сортировки меняем местами операнды
            let (net1, net2) = ascending ? (a, b) : (b, a)
            switch key {
            case "bssid": return net1.bssid < net2.bssid
            case "band": return net1.band < net2.band
            case "channel": return net1.channel < net2.channel
            case "channelWidth": return net1.channelWidth < net2.channelWidth
            case "generation": return net1.generation < net2.generation
            case "maxRate": return net1.maxRate < net2.maxRate
            case "mode": return net1.mode < net2.mode
            case "ssid": return net1.ssid < net2.ssid
            case "security": return net1.security < net2.security
            case "seen": return net1.seen < net2.seen
            case "signal": return net1.signal < net2.signal
            case "vendor": return net1.vendor < net2.vendor
            case "centerFrequency": return (net1.centerFrequency ?? 0) < (net2.centerFrequency ?? 0)
            case "countryCode": return (net1.countryCode ?? "") < (net2.countryCode ?? "")
            case "deviceName": return (net1.deviceName ?? "") < (net2.deviceName ?? "")
            case "firstSeen": return (net1.firstSeen ?? Date.distantPast) < (net2.firstSeen ?? Date.distantPast)
            case "lastSeen": return (net1.lastSeen ?? Date.distantPast) < (net2.lastSeen ?? Date.distantPast)
            case "minRate": return (net1.minRate ?? 0) < (net2.minRate ?? 0)
            case "noise": return (net1.noise ?? 0) < (net2.noise ?? 0)
            case "snr": return (net1.snr ?? 0) < (net2.snr ?? 0)
            case "stations": return (net1.stations ?? 0) < (net2.stations ?? 0)
            case "streams": return (net1.streams ?? 0) < (net2.streams ?? 0)
            case "type": return (net1.type ?? "") < (net2.type ?? "")
            case "wps": return (net1.wps ?? "") < (net2.wps ?? "")
            default: return false
            }
        }
    }
    
    deinit {
        refreshTimer?.invalidate()
        scanTask?.cancel()
    }
}
