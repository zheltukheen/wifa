import Foundation

enum WiFiBand: Int, Codable {
    case unknown = 0
    case band24 = 1
    case band5 = 2
    case band6 = 3

    var label: String {
        switch self {
        case .band24: return "2.4GHz"
        case .band5: return "5GHz"
        case .band6: return "6GHz"
        case .unknown: return "-"
        }
    }

    var sortOrder: Int { rawValue }
}

enum WiFiStandard: Int, Codable {
    case unknown = 0
    case mode11b = 1
    case mode11a = 2
    case mode11g = 3
    case mode11n = 4
    case mode11ac = 5
    case mode11ax = 6

    var label: String {
        switch self {
        case .mode11b: return "11b"
        case .mode11a: return "11a"
        case .mode11g: return "11g"
        case .mode11n: return "11n"
        case .mode11ac: return "11ac"
        case .mode11ax: return "11ax"
        case .unknown: return "-"
        }
    }

    var sortOrder: Int { rawValue }
}

struct InformationElement: Identifiable, Equatable {
    let id: String
    let elementId: Int
    let length: Int
    let name: String
    let summary: String
    let detailLines: [String]
    let rawHex: String

    var displayId: String { "\(elementId)" }
}

struct NetworkModel: Identifiable, Equatable {
    let id: String

    // Основные поля
    let bssid: String
    let ssid: String
    let band: WiFiBand
    let channel: Int
    let channelWidthMHz: Int
    let generation: WiFiStandard
    let security: String
    let vendor: String
    let mode: String
    let signal: Int
    let noise: Int?
    let snr: Int?

    // Частично доступные данные
    let basicRates: [Double]?
    let minBasicRate: Double?
    let maxBasicRate: Double?
    let minRate: Double?
    let maxRate: Double?
    let centerFrequency: Int?
    let channelUtilization: Int?
    let beaconInterval: Int?
    let beaconRate: Double?
    let beaconAirtime: Double?
    let beaconMode: String?
    let countryCode: String?
    let fastTransition: Bool?
    let protectionMode: String?
    let stations: Int?
    let clients: Int?
    let streams: Int?
    let type: String?
    let wps: String?
    let ieCount: Int?
    let ieTotalLength: Int?
    let ratesEstimated: Bool
    let informationElements: [InformationElement]

    // Временные метрики
    let count: Int
    let firstSeen: Date?
    let lastSeen: Date?

    var seen: Int {
        guard let lastSeen else { return 0 }
        let seconds = Int(Date().timeIntervalSince(lastSeen))
        return max(0, seconds)
    }

    var uptimeSeconds: Int? {
        guard let firstSeen else { return nil }
        let seconds = Int(Date().timeIntervalSince(firstSeen))
        return max(0, seconds)
    }

    var bandLabel: String { band.label }

    var channelWidthLabel: String {
        channelWidthMHz > 0 ? "\(channelWidthMHz)" : "-"
    }

    var generationLabel: String { generation.label }

    var maxRateLabel: String {
        guard let maxRate, maxRate > 0 else { return "-" }
        return String(format: "%.0f", maxRate)
    }

    var minRateLabel: String {
        guard let minRate, minRate > 0 else { return "-" }
        return String(format: "%.0f", minRate)
    }

    var maxBasicRateLabel: String {
        guard let maxBasicRate, maxBasicRate > 0 else { return "-" }
        return String(format: "%.0f", maxBasicRate)
    }

    var minBasicRateLabel: String {
        guard let minBasicRate, minBasicRate > 0 else { return "-" }
        return String(format: "%.0f", minBasicRate)
    }

    var basicRatesLabel: String {
        guard let basicRates, !basicRates.isEmpty else { return "-" }
        let values = basicRates.map { String(format: "%.0f", $0) }
        return values.joined(separator: ", ")
    }

    var centerFrequencyLabel: String {
        guard let centerFrequency else { return "-" }
        return "\(centerFrequency)"
    }

    var noiseLabel: String {
        guard let noise else { return "-" }
        return "\(noise)"
    }

    var snrLabel: String {
        guard let snr else { return "-" }
        return "\(snr)"
    }

    var wideChannelLabel: String {
        channelWidthMHz >= 80 ? "Yes" : "No"
    }

    var displaySSID: String {
        ssid.isEmpty ? "<Hidden>" : ssid
    }

    var displayName: String {
        if !ssid.isEmpty { return ssid }
        if !bssid.isEmpty { return bssid }
        return "<Hidden>"
    }
}
