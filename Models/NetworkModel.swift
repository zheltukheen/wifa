import Foundation

struct NetworkModel: Identifiable {
    let id = UUID()
    
    // Видимые по умолчанию
    let bssid: String
    let band: String
    let channel: Int
    let channelWidth: String
    let generation: String
    let maxRate: Double
    let mode: String
    let ssid: String
    let security: String
    let seen: Int
    let signal: Int
    let vendor: String
    
    // Скрытые по умолчанию
    let basicRates: [Double]?
    let beaconInterval: Int?
    let centerFrequency: Int?
    let channelUtilization: Int?
    let countryCode: String?
    let deviceName: String?
    let fastTransition: Bool?
    let firstSeen: Date?
    let lastSeen: Date?
    let minRate: Double?
    let noise: Int?
    let protectionMode: String?
    let snr: Int?
    let stations: Int?
    let streams: Int?
    let type: String?
    let wps: String?
}
