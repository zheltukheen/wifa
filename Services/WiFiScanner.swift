import Foundation
import CoreWLAN

enum WiFiError: LocalizedError {
    case interfaceNotFound
    case wifiPoweredOff
    case scanFailed(String)

    var errorDescription: String? {
        switch self {
        case .interfaceNotFound:
            return "Wi-Fi interface not found"
        case .wifiPoweredOff:
            return "Wi-Fi is off"
        case .scanFailed(let message):
            return message.isEmpty ? "Wi-Fi scan failed" : message
        }
    }
}

actor WiFiScanner {
    func scan() async throws -> [NetworkModel] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let networks = try Self.performScan()
                    continuation.resume(returning: networks)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func performScan() throws -> [NetworkModel] {
        let client = CWWiFiClient.shared()
        guard let interface = client.interface() else {
            throw WiFiError.interfaceNotFound
        }
        guard interface.powerOn() else {
            throw WiFiError.wifiPoweredOff
        }

        let results: Set<CWNetwork>
        do {
            results = try interface.scanForNetworks(withName: nil, includeHidden: true)
        } catch {
            throw WiFiError.scanFailed(error.localizedDescription)
        }

        return results.map { makeModel(from: $0) }
    }

    private static func makeModel(from network: CWNetwork) -> NetworkModel {
        let ssid = network.ssid ?? ""
        let bssid = (network.bssid ?? "").uppercased()
        let channelNumber = network.wlanChannel?.channelNumber ?? 0
        let band = mapBand(network.wlanChannel?.channelBand)
        let channelWidthMHz = mapChannelWidth(network.wlanChannel?.channelWidth)
        let generation = mapGeneration(network)
        let security = securityDescription(for: network)
        let vendor = bssid.isEmpty ? "-" : OUIParser.vendor(for: bssid)
        let mode = network.ibss ? "IBSS" : "Infrastructure"

        let noiseValue = Int(network.noiseMeasurement)
        let noise = noiseValue == 0 ? nil : noiseValue
        let rssi = Int(network.rssiValue)
        let snr = noise.map { rssi - $0 }
        let beaconInterval = network.beaconInterval == 0 ? nil : Int(network.beaconInterval)
        let countryCode = network.countryCode
        let ieData = network.informationElementData
        let ieTotalLength = ieData?.count
        let centerFrequency = centerFrequency(channel: channelNumber, band: band)
        let rateEstimate = estimateRates(generation: generation, widthMHz: channelWidthMHz)
        let parsedIE = parseInformationElements(ieData)
        let beaconAirtime = estimateBeaconAirtime(beaconInterval: beaconInterval, beaconRate: rateEstimate.beaconRate)

        let id = makeStableId(ssid: ssid, bssid: bssid, channel: channelNumber, band: band, widthMHz: channelWidthMHz, security: security)

        return NetworkModel(
            id: id,
            bssid: bssid,
            ssid: ssid,
            band: band,
            channel: channelNumber,
            channelWidthMHz: channelWidthMHz,
            generation: generation,
            security: security,
            vendor: vendor,
            mode: mode,
            signal: rssi,
            noise: noise,
            snr: snr,
            basicRates: rateEstimate.basicRates,
            minBasicRate: rateEstimate.minBasicRate,
            maxBasicRate: rateEstimate.maxBasicRate,
            minRate: rateEstimate.minRate,
            maxRate: rateEstimate.maxRate,
            centerFrequency: centerFrequency,
            channelUtilization: parsedIE.channelUtilization,
            beaconInterval: beaconInterval,
            beaconRate: rateEstimate.beaconRate,
            beaconAirtime: beaconAirtime,
            beaconMode: mode,
            countryCode: countryCode,
            fastTransition: parsedIE.fastTransition,
            protectionMode: parsedIE.protectionMode,
            stations: parsedIE.stations,
            clients: parsedIE.clients ?? parsedIE.stations,
            streams: parsedIE.streams,
            type: mode,
            wps: "Unknown",
            ieCount: parsedIE.ieCount,
            ieTotalLength: ieTotalLength,
            ratesEstimated: rateEstimate.isEstimated,
            informationElements: parsedIE.elements,
            count: 0,
            firstSeen: nil,
            lastSeen: nil
        )
    }

    private static func makeStableId(ssid: String, bssid: String, channel: Int, band: WiFiBand, widthMHz: Int, security: String) -> String {
        if !bssid.isEmpty { return bssid }
        let safeSSID = ssid.isEmpty ? "<Hidden>" : ssid
        return "\(safeSSID)|\(band.rawValue)|\(channel)|\(widthMHz)|\(security)"
    }

    private static func mapBand(_ band: CWChannelBand?) -> WiFiBand {
        switch band {
        case .band2GHz: return .band24
        case .band5GHz: return .band5
        case .band6GHz: return .band6
        default: return .unknown
        }
    }

    private static func mapChannelWidth(_ width: CWChannelWidth?) -> Int {
        switch width {
        case .width20MHz: return 20
        case .width40MHz: return 40
        case .width80MHz: return 80
        case .width160MHz: return 160
        default: return 0
        }
    }

    private static func mapGeneration(_ network: CWNetwork) -> WiFiStandard {
        if network.supportsPHYMode(.mode11ax) { return .mode11ax }
        if network.supportsPHYMode(.mode11ac) { return .mode11ac }
        if network.supportsPHYMode(.mode11n) { return .mode11n }
        if network.supportsPHYMode(.mode11g) { return .mode11g }
        if network.supportsPHYMode(.mode11a) { return .mode11a }
        if network.supportsPHYMode(.mode11b) { return .mode11b }
        return .unknown
    }

    private static func centerFrequency(channel: Int, band: WiFiBand) -> Int? {
        guard channel > 0 else { return nil }
        switch band {
        case .band24:
            if channel == 14 { return 2484 }
            return 2407 + (channel * 5)
        case .band5:
            return 5000 + (channel * 5)
        case .band6:
            return 5950 + (channel * 5)
        case .unknown:
            return nil
        }
    }

    private struct RateEstimate {
        let basicRates: [Double]?
        let minBasicRate: Double?
        let maxBasicRate: Double?
        let minRate: Double?
        let maxRate: Double?
        let beaconRate: Double?
        let isEstimated: Bool
    }

    private static func estimateRates(generation: WiFiStandard, widthMHz: Int) -> RateEstimate {
        let basicRates: [Double]?
        let minRate: Double?
        let maxRate: Double?

        switch generation {
        case .mode11b:
            basicRates = [1, 2, 5.5, 11]
            minRate = 1
            maxRate = 11
        case .mode11a, .mode11g:
            basicRates = [6, 9, 12, 18, 24, 36, 48, 54]
            minRate = 6
            maxRate = 54
        case .mode11n:
            basicRates = [6, 12, 24, 54]
            minRate = 6
            maxRate = rateFor(widthMHz: widthMHz, defaults: (20, 72), (40, 150), (80, 300), (160, 300))
        case .mode11ac:
            basicRates = [6, 12, 24, 54]
            minRate = 6
            maxRate = rateFor(widthMHz: widthMHz, defaults: (20, 87), (40, 200), (80, 433), (160, 867))
        case .mode11ax:
            basicRates = [6, 12, 24, 54]
            minRate = 6
            maxRate = rateFor(widthMHz: widthMHz, defaults: (20, 143), (40, 286), (80, 600), (160, 1200))
        case .unknown:
            basicRates = nil
            minRate = nil
            maxRate = nil
        }

        let minBasicRate = basicRates?.min()
        let maxBasicRate = basicRates?.max()
        let beaconRate = maxBasicRate
        let isEstimated = maxRate != nil || minRate != nil || basicRates != nil

        return RateEstimate(
            basicRates: basicRates,
            minBasicRate: minBasicRate,
            maxBasicRate: maxBasicRate,
            minRate: minRate,
            maxRate: maxRate,
            beaconRate: beaconRate,
            isEstimated: isEstimated
        )
    }

    private static func rateFor(widthMHz: Int, defaults: (Int, Double), _ other1: (Int, Double), _ other2: (Int, Double), _ other3: (Int, Double)) -> Double? {
        let mapping = [defaults, other1, other2, other3]
        if let match = mapping.first(where: { $0.0 == widthMHz }) {
            return match.1
        }
        let fallback = mapping.first(where: { $0.0 == 20 })?.1 ?? 0
        return fallback > 0 ? fallback : nil
    }

    private static func securityDescription(for network: CWNetwork) -> String {
        let ordered: [(CWSecurity, String)] = [
            (.wpa3Enterprise, "WPA3 Enterprise"),
            (.wpa3Personal, "WPA3 Personal"),
            (.wpa3Transition, "WPA3 Transition"),
            (.oweTransition, "OWE Transition"),
            (.OWE, "OWE"),
            (.wpa2Enterprise, "WPA2 Enterprise"),
            (.wpa2Personal, "WPA2 Personal"),
            (.enterprise, "WPA Enterprise"),
            (.personal, "WPA Personal"),
            (.wpaEnterprise, "WPA Enterprise"),
            (.wpaPersonal, "WPA Personal"),
            (.dynamicWEP, "Dynamic WEP"),
            (.WEP, "WEP"),
            (.none, "Open")
        ]

        for (security, label) in ordered where network.supportsSecurity(security) {
            return label
        }
        return "Unknown"
    }

    // MARK: - Information Elements Parsing

    private struct ParsedIEInfo {
        let elements: [InformationElement]
        let ieCount: Int?
        let channelUtilization: Int?
        let stations: Int?
        let clients: Int?
        let streams: Int?
        let fastTransition: Bool?
        let protectionMode: String?

        static let empty = ParsedIEInfo(
            elements: [],
            ieCount: nil,
            channelUtilization: nil,
            stations: nil,
            clients: nil,
            streams: nil,
            fastTransition: nil,
            protectionMode: nil
        )
    }

    private static func parseInformationElements(_ data: Data?) -> ParsedIEInfo {
        guard let data, !data.isEmpty else { return .empty }

        var elements: [InformationElement] = []
        var index = 0
        var sequence = 0

        var supportedRates: [RateEntry] = []
        var supportedRatesLength = 0
        var supportedRatesInsertIndex: Int? = nil
        var supportedRatesId: Int? = nil

        var stations: Int? = nil
        var clients: Int? = nil
        var channelUtilization: Int? = nil
        var fastTransition: Bool? = nil
        var protectionMode: String? = nil
        var htStreams: Int? = nil
        var vhtStreams: Int? = nil
        var heStreams: Int? = nil

        while index + 2 <= data.count {
            let elementId = Int(data[index])
            let length = Int(data[index + 1])
            index += 2
            guard index + length <= data.count else { break }

            let payload = data.subdata(in: index..<(index + length))
            index += length

            switch elementId {
            case 1, 50:
                if supportedRatesInsertIndex == nil { supportedRatesInsertIndex = elements.count }
                supportedRatesLength += length
                if elementId == 1 { supportedRatesId = 1 }
                if elementId == 50, supportedRatesId == nil { supportedRatesId = 50 }
                supportedRates.append(contentsOf: decodeSupportedRates(payload))
                continue
            case 11:
                let parsed = parseBssLoad(payload)
                stations = parsed.stationCount ?? stations
                clients = parsed.stationCount ?? clients
                channelUtilization = parsed.channelUtilization ?? channelUtilization
            case 45:
                htStreams = max(htStreams ?? 0, parseHtStreams(payload))
            case 61:
                protectionMode = parseHtProtection(payload) ?? protectionMode
            case 48:
                if let rsn = parseRsn(payload) {
                    fastTransition = rsn.fastTransition
                }
            case 191:
                vhtStreams = max(vhtStreams ?? 0, parseVhtStreams(payload))
            case 255:
                heStreams = max(heStreams ?? 0, parseHeStreams(payload))
            default:
                break
            }

            let element = buildInformationElement(
                elementId: elementId,
                length: length,
                payload: payload
            )
            sequence += 1
            let withId = InformationElement(
                id: "\(elementId)-\(sequence)",
                elementId: elementId,
                length: length,
                name: element.name,
                summary: element.summary,
                detailLines: element.detailLines,
                rawHex: element.rawHex
            )
            elements.append(withId)
        }

        if !supportedRates.isEmpty {
            let summary = formatSupportedRates(supportedRates)
            let rawHex = "-"
            let detailLines = supportedRateDetailLines(supportedRates)
            let supported = InformationElement(
                id: "1-0",
                elementId: supportedRatesId ?? 1,
                length: supportedRatesLength,
                name: "Supported Rates",
                summary: summary,
                detailLines: detailLines,
                rawHex: rawHex
            )
            if let insertIndex = supportedRatesInsertIndex, insertIndex <= elements.count {
                elements.insert(supported, at: insertIndex)
            } else {
                elements.append(supported)
            }
        }

        let streamCandidates = [htStreams, vhtStreams, heStreams].compactMap { $0 }
        let streams = streamCandidates.max()

        return ParsedIEInfo(
            elements: elements,
            ieCount: elements.isEmpty ? nil : elements.count,
            channelUtilization: channelUtilization,
            stations: stations,
            clients: clients,
            streams: streams == 0 ? nil : streams,
            fastTransition: fastTransition,
            protectionMode: protectionMode
        )
    }

    private struct ElementDetails {
        let name: String
        let summary: String
        let detailLines: [String]
        let rawHex: String
    }

    private static func buildInformationElement(elementId: Int, length: Int, payload: Data) -> ElementDetails {
        let rawHex = hexString(payload)

        switch elementId {
        case 0:
            let ssid = decodeSSID(payload)
            return ElementDetails(
                name: "SSID",
                summary: ssid.isEmpty ? "<Hidden>" : ssid,
                detailLines: [
                    "SSID: \(ssid.isEmpty ? "<Hidden>" : ssid)",
                    "SSID Data: \(rawHex)"
                ],
                rawHex: rawHex
            )
        case 3:
            let channel = payload.first.map { Int($0) } ?? 0
            let summary = "Current channel: \(channel)"
            return ElementDetails(
                name: "DSSS Parameter Set",
                summary: summary,
                detailLines: ["Current channel: \(channel)"],
                rawHex: rawHex
            )
        case 5:
            let dtimCount = payload.count > 0 ? payload[0] : 0
            let dtimPeriod = payload.count > 1 ? payload[1] : 0
            let summary = "DTIM Count: \(dtimCount), DTIM Period: \(dtimPeriod)"
            return ElementDetails(
                name: "Traffic Indication Map",
                summary: summary,
                detailLines: [
                    "DTIM Count: \(dtimCount)",
                    "DTIM Period: \(dtimPeriod)"
                ],
                rawHex: rawHex
            )
        case 7:
            let countryInfo = decodeCountryDetails(payload)
            return ElementDetails(name: "Country", summary: countryInfo.summary, detailLines: countryInfo.detailLines, rawHex: rawHex)
        case 32:
            let value = payload.first.map { Int($0) } ?? 0
            let summary = "\(value) dB"
            return ElementDetails(
                name: "Power Constraint",
                summary: summary,
                detailLines: ["Power Constraint: \(summary)"],
                rawHex: rawHex
            )
        case 35:
            let tx = payload.count > 0 ? payload[0] : 0
            let margin = payload.count > 1 ? payload[1] : 0
            let summary = "Transmit Power: \(tx) dBm"
            return ElementDetails(
                name: "TPC Report",
                summary: summary,
                detailLines: [
                    "Transmit Power: \(tx) dBm",
                    "Link Margin: \(margin) dB"
                ],
                rawHex: rawHex
            )
        case 48:
            if let rsn = parseRsn(payload) {
                var lines: [String] = []
                lines.append("Group Cipher: \(rsn.groupCipher)")
                lines.append("Pairwise Cipher(s): \(rsn.pairwise.isEmpty ? "-" : rsn.pairwise.joined(separator: ", "))")
                lines.append("AKM Suite(s): \(rsn.akms.isEmpty ? "-" : rsn.akms.joined(separator: ", "))")
                if !rsn.capabilities.isEmpty {
                    lines.append("RSN Capabilities: \(rsn.capabilities.joined(separator: ", "))")
                }
                return ElementDetails(
                    name: "RSNE",
                    summary: rsn.summary,
                    detailLines: lines,
                    rawHex: rawHex
                )
            }
            return ElementDetails(name: "RSNE", summary: "Raw: \(rawHex)", detailLines: ["Raw: \(rawHex)"], rawHex: rawHex)
        case 70:
            let summary = decodeRmCapabilities(payload)
            return ElementDetails(
                name: "RM Enabled Capabilities",
                summary: summary,
                detailLines: ["RM Enabled Capabilities: \(summary)"],
                rawHex: rawHex
            )
        case 45:
            let summary = decodeHtCapabilities(payload)
            return ElementDetails(
                name: "HT Capabilities",
                summary: summary,
                detailLines: ["HT Capabilities: \(summary)"],
                rawHex: rawHex
            )
        case 61:
            let summary = decodeHtOperation(payload)
            return ElementDetails(
                name: "HT Operation",
                summary: summary,
                detailLines: ["HT Operation: \(summary)"],
                rawHex: rawHex
            )
        case 127:
            let summary = decodeExtendedCapabilities(payload)
            return ElementDetails(
                name: "Extended Capabilities",
                summary: summary,
                detailLines: ["Extended Capabilities: \(summary)"],
                rawHex: rawHex
            )
        case 191:
            let summary = decodeVhtCapabilities(payload)
            return ElementDetails(
                name: "VHT Capabilities",
                summary: summary,
                detailLines: ["VHT Capabilities: \(summary)"],
                rawHex: rawHex
            )
        case 192:
            let summary = decodeVhtOperation(payload)
            return ElementDetails(
                name: "VHT Operation",
                summary: summary,
                detailLines: ["VHT Operation: \(summary)"],
                rawHex: rawHex
            )
        case 195:
            let summary = "Local EIRP"
            return ElementDetails(
                name: "Transmit Power Envelope",
                summary: summary,
                detailLines: ["Transmit Power Envelope: \(summary)"],
                rawHex: rawHex
            )
        case 221:
            let vendor = decodeVendorSpecific(payload)
            return ElementDetails(name: vendor.name, summary: vendor.summary, detailLines: vendor.detailLines, rawHex: rawHex)
        case 255:
            let ext = decodeExtensionElement(payload)
            return ElementDetails(name: ext.name, summary: ext.summary, detailLines: ext.detailLines, rawHex: rawHex)
        default:
            let name = defaultElementName(for: elementId)
            return ElementDetails(name: name, summary: "Raw: \(rawHex)", detailLines: ["Raw: \(rawHex)"], rawHex: rawHex)
        }
    }

    private static func decodeSSID(_ data: Data) -> String {
        if let ssid = String(data: data, encoding: .utf8) {
            return ssid.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    private struct RateEntry {
        let value: Double
        let isBasic: Bool
    }

    private static func decodeSupportedRates(_ data: Data) -> [RateEntry] {
        data.map { byte in
            RateEntry(
                value: Double(byte & 0x7F) * 0.5,
                isBasic: (byte & 0x80) != 0
            )
        }
    }

    private static func formatSupportedRates(_ rates: [RateEntry]) -> String {
        guard !rates.isEmpty else { return "-" }
        let formatted = rates.map { entry -> String in
            let rate = entry.value
            if rate.truncatingRemainder(dividingBy: 1) == 0 {
                return entry.isBasic ? "\(Int(rate))(B)" : "\(Int(rate))"
            }
            let value = String(format: "%.1f", rate)
            return entry.isBasic ? "\(value)(B)" : value
        }
        return "\(formatted.joined(separator: ", ")) Mbps"
    }

    private static func supportedRateDetailLines(_ rates: [RateEntry]) -> [String] {
        rates.map { entry in
            let rate = entry.value
            let rateText: String
            if rate.truncatingRemainder(dividingBy: 1) == 0 {
                rateText = "\(Int(rate))"
            } else {
                rateText = String(format: "%.1f", rate)
            }
            let modulation = rate <= 11 ? "DSSS" : "OFDM"
            var value = "\(rateText) Mbps (\(modulation))"
            if entry.isBasic { value += " (BSS Basic Rate)" }
            return "Supported Rate: \(value)"
        }
    }

    private static func decodeCountryDetails(_ data: Data) -> (summary: String, detailLines: [String]) {
        guard data.count >= 3 else { return (summary: "-", detailLines: ["Country Code: -"]) }
        let code = String(bytes: data.prefix(2), encoding: .ascii) ?? "-"
        let envChar = data[2]
        let envLabel: String
        switch envChar {
        case 0x20: envLabel = "All"
        case 0x49: envLabel = "Indoor"
        case 0x4F: envLabel = "Outdoor"
        default: envLabel = String(UnicodeScalar(envChar))
        }
        let summary = "\(code) (\(envLabel))"
        var lines: [String] = [
            "Country Code: \(code)",
            "Environment: \(envLabel)"
        ]
        if data.count > 3 {
            var index = 3
            while index + 2 < data.count {
                let first = Int(data[index])
                let count = Int(data[index + 1])
                let power = Int(data[index + 2])
                let last = max(first, first + count - 1)
                lines.append("Country Info: Channels \(first) to \(last): \(power) dBm")
                index += 3
            }
        }
        return (summary: summary, detailLines: lines)
    }

    private static func decodeRmCapabilities(_ data: Data) -> String {
        guard data.count >= 5 else { return "Raw: \(hexString(data))" }
        let names: [(Int, Int, String)] = [
            (0, 0, "Link Measurement"),
            (0, 1, "Neighbor Report"),
            (0, 2, "Beacon Passive Measurement"),
            (0, 3, "Beacon Active Measurement"),
            (0, 4, "Beacon Table Measurement"),
            (0, 5, "LCI Measurement"),
            (0, 6, "Location Civic Measurement"),
            (0, 7, "FTM Range Reporting")
        ]
        var features: [String] = []
        for (byteIndex, bit, name) in names {
            if byteIndex < data.count, (data[byteIndex] & (1 << bit)) != 0 {
                features.append(name)
            }
        }
        if features.isEmpty { return "Raw: \(hexString(data))" }
        let list = features.count > 9 ? features.prefix(9).joined(separator: ", ") + ", …" : features.joined(separator: ", ")
        return list
    }

    private static func decodeHtCapabilities(_ data: Data) -> String {
        guard data.count >= 4 else { return "Raw: \(hexString(data))" }
        let cap = UInt16(data[0]) | (UInt16(data[1]) << 8)
        let supports40 = (cap & (1 << 1)) != 0
        let shortGi20 = (cap & (1 << 5)) != 0
        let shortGi40 = (cap & (1 << 6)) != 0
        var parts: [String] = [supports40 ? "20/40 MHz" : "20 MHz"]
        if shortGi20 { parts.append("Short GI for 20 MHz") }
        if shortGi40 { parts.append("Short GI for 40 MHz") }
        let streams = parseHtStreams(data)
        if streams > 0 { parts.append("\(streams) Spatial Streams") }
        return parts.joined(separator: ", ")
    }

    private static func parseHtStreams(_ data: Data) -> Int {
        guard data.count >= 16 else { return 0 }
        let mcsBytes = data[3..<11]
        var count = 0
        for byte in mcsBytes.prefix(4) where byte != 0 {
            count += 1
        }
        return count
    }

    private static func decodeHtOperation(_ data: Data) -> String {
        guard data.count >= 3 else { return "Raw: \(hexString(data))" }
        let primaryChannel = data[0]
        let htInfo = data[1]
        let secondaryOffset = htInfo & 0x3
        let secondaryLabel: String
        switch secondaryOffset {
        case 1: secondaryLabel = "+1"
        case 3: secondaryLabel = "-1"
        default: secondaryLabel = "0"
        }
        let widthSupported = (htInfo & 0x4) != 0
        let protection = parseHtProtection(data) ?? "Unknown"
        return "Primary Channel: \(primaryChannel) (\(widthSupported ? "Any Width Supported" : "20 MHz Only")), Secondary Channel Offset: \(secondaryLabel), \(protection)"
    }

    private static func parseHtProtection(_ data: Data) -> String? {
        guard data.count >= 3 else { return nil }
        let htProtection = data[2] & 0x3
        switch htProtection {
        case 0: return "No protection mode"
        case 1: return "Non-member protection mode"
        case 2: return "20 MHz protection mode"
        case 3: return "Mixed mode"
        default: return nil
        }
    }

    private static func decodeExtendedCapabilities(_ data: Data) -> String {
        guard data.count >= 4 else { return "Raw: \(hexString(data))" }
        let features: [(Int, Int, String)] = [
            (2, 0, "Extended Channel Switching"),
            (2, 4, "TFS"),
            (2, 5, "WNM Sleep Mode"),
            (2, 6, "TIM Broadcast"),
            (2, 7, "BSS Transition"),
            (3, 1, "SSID List"),
            (3, 6, "Operating Mode Notification"),
            (4, 2, "TWT Responder")
        ]
        var parts: [String] = []
        for (byteIndex, bit, name) in features {
            if byteIndex < data.count, (data[byteIndex] & (1 << bit)) != 0 {
                parts.append(name)
            }
        }
        return parts.isEmpty ? "Raw: \(hexString(data))" : parts.joined(separator: ", ")
    }

    private static func decodeVhtCapabilities(_ data: Data) -> String {
        guard data.count >= 12 else { return "Raw: \(hexString(data))" }
        let capInfo = UInt32(data[0]) | (UInt32(data[1]) << 8) | (UInt32(data[2]) << 16) | (UInt32(data[3]) << 24)
        let shortGi80 = (capInfo & (1 << 5)) != 0
        let shortGi160 = (capInfo & (1 << 6)) != 0
        var parts: [String] = []
        if shortGi80 { parts.append("Short GI for 80 MHz") }
        if shortGi160 { parts.append("Short GI for 160 MHz") }
        let streams = parseVhtStreams(data)
        if streams > 0 { parts.append("\(streams) Spatial Streams") }
        return parts.isEmpty ? "Raw: \(hexString(data))" : parts.joined(separator: ", ")
    }

    private static func parseVhtStreams(_ data: Data) -> Int {
        guard data.count >= 6 else { return 0 }
        let rxMap = UInt16(data[4]) | (UInt16(data[5]) << 8)
        var streams = 0
        for i in 0..<8 {
            let value = (rxMap >> (i * 2)) & 0x3
            if value != 3 { streams += 1 }
        }
        return streams
    }

    private static func decodeVhtOperation(_ data: Data) -> String {
        guard data.count >= 3 else { return "Raw: \(hexString(data))" }
        let channelWidth = data[0]
        let widthLabel: String
        switch channelWidth {
        case 0: widthLabel = "20/40 MHz"
        case 1: widthLabel = "80 MHz"
        case 2: widthLabel = "160 MHz or 80+80 MHz"
        default: widthLabel = "Unknown"
        }
        let seg0 = data[1]
        let seg1 = data[2]
        return "Channel Width: \(widthLabel), Channel Center Frequency Segment 0: \(seg0), Channel Center Frequency Segment 1: \(seg1)"
    }

    private static func decodeExtensionElement(_ data: Data) -> (name: String, summary: String, detailLines: [String]) {
        guard let extId = data.first else {
            return (name: "Extension", summary: "Raw: \(hexString(data))", detailLines: ["Raw: \(hexString(data))"])
        }
        let payload = data.dropFirst()
        switch extId {
        case 35:
            let info = decodeHeCapabilities(Data(payload))
            return (name: "Extension: HE Capabilities", summary: info.summary, detailLines: info.detailLines)
        case 36:
            let info = decodeHeOperation(Data(payload))
            return (name: "Extension: HE Operation", summary: info.summary, detailLines: info.detailLines)
        case 55:
            let summary = decodeSpatialReuse(Data(payload))
            return (name: "Extension: Spatial Reuse Parameter Set", summary: summary, detailLines: [summary])
        case 12:
            let summary = "Wireless Multimedia (WMM)"
            return (name: "Extension: MU EDCA Parameter Set", summary: summary, detailLines: ["MU EDCA Parameter Set: \(summary)"])
        default:
            return (name: "Extension", summary: "Raw: \(hexString(data))", detailLines: ["Raw: \(hexString(data))"])
        }
    }

    private static func decodeHeCapabilities(_ data: Data) -> (summary: String, detailLines: [String]) {
        guard !data.isEmpty else {
            return (summary: "HE Capabilities", detailLines: ["HE Capabilities"])
        }
        var details: [String] = []
        var offset = 0

        let macLen = min(6, data.count)
        let mac = data.prefix(macLen)
        offset += macLen
        details.append("HE MAC Capabilities: \(hexString(mac))")

        if offset < data.count {
            let phyLen = min(11, data.count - offset)
            let phy = data.subdata(in: offset..<(offset + phyLen))
            offset += phyLen
            details.append("HE PHY Capabilities: \(hexString(phy))")
        }

        var streams: Int? = nil
        if offset + 2 <= data.count {
            let heMcs = data.subdata(in: offset..<(offset + 2))
            streams = parseHeStreams(heMcs)
            details.append("HE MCS/NSS (80MHz RX): \(hexString(heMcs))")
        }

        var summaryParts: [String] = []
        if let streams, streams > 0 {
            summaryParts.append("\(streams) Spatial Streams")
        }
        let summary = summaryParts.isEmpty ? "HE Capabilities" : summaryParts.joined(separator: "; ")
        details.insert("HE Capabilities: \(summary)", at: 0)
        return (summary: summary, detailLines: details)
    }

    private static func decodeHeOperation(_ data: Data) -> (summary: String, detailLines: [String]) {
        guard data.count >= 1 else { return (summary: "HE Operation", detailLines: ["HE Operation"]) }
        let color = data[0] & 0x3F
        let disabled = (data[0] & 0x40) != 0
        var summary = "BSS Color: \(color)"
        if disabled { summary += " (Disabled)" }
        let details = [summary, "Raw: \(hexString(data))"]
        return (summary: summary, detailLines: details)
    }

    private static func decodeSpatialReuse(_ data: Data) -> String {
        guard let first = data.first else { return "Spatial Reuse Parameters" }
        var parts: [String] = []
        if (first & 0x01) != 0 { parts.append("PSR Disallowed") }
        if (first & 0x02) != 0 { parts.append("Non-SRG OBSS PD SR Disallowed") }
        return parts.isEmpty ? "Spatial Reuse Parameters" : parts.joined(separator: ", ")
    }

    private static func parseHeStreams(_ data: Data) -> Int {
        guard data.count >= 2 else { return 0 }
        let rxMap = UInt16(data[0]) | (UInt16(data[1]) << 8)
        var streams = 0
        for i in 0..<8 {
            let value = (rxMap >> (i * 2)) & 0x3
            if value != 3 { streams += 1 }
        }
        return streams
    }

    private static func decodeVendorSpecific(_ data: Data) -> (name: String, summary: String, detailLines: [String]) {
        guard data.count >= 3 else {
            return (name: "Vendor Specific", summary: "Raw: \(hexString(data))", detailLines: ["Raw: \(hexString(data))"])
        }
        let oui = [data[0], data[1], data[2]]
        let ouiString = oui.map { String(format: "%02X", $0) }.joined()
        let vendor = OUIParser.vendor(for: ouiString)
        let vendorName: String
        if vendor == "-" || vendor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            vendorName = "Vendor Specific"
        } else if vendor.localizedCaseInsensitiveContains("Qualcomm") {
            vendorName = "Vendor Specific: Qualcomm"
        } else if vendor.localizedCaseInsensitiveContains("Microsoft") {
            vendorName = "Vendor Specific: Microsoft"
        } else if vendor.localizedCaseInsensitiveContains("TP-Link") {
            vendorName = "Vendor Specific: TP-Link"
        } else {
            vendorName = "Vendor Specific: \(vendor)"
        }

        if oui == [0x00, 0x50, 0xF2], data.count >= 4 {
            let type = data[3]
            if type == 2 {
                return (name: vendorName, summary: "Wireless Multimedia (WMM)", detailLines: ["WMM: Wireless Multimedia (WMM)"])
            }
            if type == 4 {
                let wps = decodeWpsAttributes(Data(data.dropFirst(4)))
                return (name: vendorName, summary: wps.summary, detailLines: wps.detailLines)
            }
        }

        return (name: vendorName, summary: vendorName, detailLines: ["Vendor: \(vendorName)"])
    }

    private struct WpsInfo {
        let summary: String
        let detailLines: [String]
    }

    private static func decodeWpsAttributes(_ data: Data) -> WpsInfo {
        var index = 0
        var configured: Bool? = nil
        var deviceName: String? = nil
        var configMethods: UInt16? = nil
        var manufacturer: String? = nil
        var modelName: String? = nil
        var modelNumber: String? = nil
        var serialNumber: String? = nil
        var primaryDeviceType: String? = nil
        var isAccessPoint: Bool = false

        while index + 4 <= data.count {
            let type = UInt16(data[index]) << 8 | UInt16(data[index + 1])
            let length = Int(UInt16(data[index + 2]) << 8 | UInt16(data[index + 3]))
            index += 4
            guard index + length <= data.count else { break }
            let value = data.subdata(in: index..<(index + length))
            index += length

            switch type {
            case 0x1044:
                configured = (value.first == 0x02)
            case 0x1011:
                deviceName = String(data: value, encoding: .utf8)
            case 0x1008:
                if value.count >= 2 {
                    configMethods = UInt16(value[0]) << 8 | UInt16(value[1])
                }
            case 0x1021:
                manufacturer = String(data: value, encoding: .utf8)
            case 0x1023:
                modelName = String(data: value, encoding: .utf8)
            case 0x1024:
                modelNumber = String(data: value, encoding: .utf8)
            case 0x1042:
                serialNumber = String(data: value, encoding: .utf8)
            case 0x1054:
                if let parsed = decodePrimaryDeviceType(value) {
                    primaryDeviceType = parsed.label
                    isAccessPoint = parsed.isAccessPoint
                }
            default:
                continue
            }
        }

        var summary = "Wi-Fi Protected Setup (WPS)"
        if configured == true { summary += "; Configured" }
        if isAccessPoint { summary += "; AP" }
        if let modelName, !modelName.isEmpty {
            summary += "; \(modelName)"
        }
        var detailLines: [String] = [summary]
        if let manufacturer, !manufacturer.isEmpty {
            detailLines.append("Manufacturer: \(manufacturer)")
        }
        if let modelName, !modelName.isEmpty {
            detailLines.append("Model: \(modelName)")
        }
        if let modelNumber, !modelNumber.isEmpty {
            detailLines.append("Model Number: \(modelNumber)")
        }
        if let serialNumber, !serialNumber.isEmpty {
            detailLines.append("Serial Number: \(serialNumber)")
        }
        if let deviceName, !deviceName.isEmpty {
            detailLines.append("Device Name: \(deviceName)")
        }
        if let primaryDeviceType, !primaryDeviceType.isEmpty {
            detailLines.append("Primary Device Type: \(primaryDeviceType)")
        }
        if let methods = configMethods {
            let methodLabels = decodeWpsConfigMethods(methods)
            if !methodLabels.isEmpty {
                detailLines.append("Methods: \(methodLabels.joined(separator: ", "))")
            }
        }
        return WpsInfo(summary: summary, detailLines: detailLines)
    }

    private static func decodeWpsConfigMethods(_ methods: UInt16) -> [String] {
        let mapping: [(UInt16, String)] = [
            (0x0001, "USB"),
            (0x0002, "Ethernet"),
            (0x0004, "Label"),
            (0x0008, "Display"),
            (0x0010, "Ext NFC Token"),
            (0x0020, "Int NFC Token"),
            (0x0040, "NFC Interface"),
            (0x0080, "PushButton"),
            (0x0100, "Keypad")
        ]
        return mapping.compactMap { (bit, label) in
            (methods & bit) != 0 ? label : nil
        }
    }

    private static func decodePrimaryDeviceType(_ data: Data) -> (label: String, isAccessPoint: Bool)? {
        guard data.count >= 8 else { return nil }
        let category = UInt16(data[0]) << 8 | UInt16(data[1])
        let subCategory = UInt16(data[6]) << 8 | UInt16(data[7])
        let categoryLabel: String
        switch category {
        case 1: categoryLabel = "Computer"
        case 2: categoryLabel = "Input Device"
        case 3: categoryLabel = "Printers/Scanners"
        case 4: categoryLabel = "Camera"
        case 5: categoryLabel = "Storage"
        case 6: categoryLabel = "Network Infrastructure"
        case 7: categoryLabel = "Display"
        case 8: categoryLabel = "Multimedia"
        case 9: categoryLabel = "Gaming"
        case 10: categoryLabel = "Telephone"
        default: categoryLabel = "Other"
        }
        let isAccessPoint = (category == 6 && subCategory == 1)
        let label = "\(categoryLabel) (Subcategory \(subCategory))"
        return (label, isAccessPoint)
    }

    private static func parseBssLoad(_ data: Data) -> (stationCount: Int?, channelUtilization: Int?) {
        guard data.count >= 5 else { return (nil, nil) }
        let stationCount = Int(UInt16(data[0]) | (UInt16(data[1]) << 8))
        let utilizationRaw = Double(data[2])
        let utilizationPercent = Int(round(utilizationRaw * 100.0 / 255.0))
        return (stationCount, utilizationPercent)
    }

    private struct RsnInfo {
        let summary: String
        let fastTransition: Bool
        let groupCipher: String
        let pairwise: [String]
        let akms: [String]
        let capabilities: [String]
    }

    private static func parseRsn(_ data: Data) -> RsnInfo? {
        var offset = 0
        guard data.count >= 4 else { return nil }

        func readUInt16() -> UInt16? {
            guard offset + 2 <= data.count else { return nil }
            let value = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
            offset += 2
            return value
        }

        func readSuite() -> (String, UInt8)? {
            guard offset + 4 <= data.count else { return nil }
            let oui = [data[offset], data[offset + 1], data[offset + 2]]
            let type = data[offset + 3]
            offset += 4
            return (cipherSuiteName(oui: oui, type: type), type)
        }

        _ = readUInt16() // version
        guard let (groupCipher, _) = readSuite() else { return nil }
        guard let pairwiseCount = readUInt16() else { return nil }

        var pairwise: [String] = []
        for _ in 0..<pairwiseCount {
            if let (cipher, _) = readSuite() { pairwise.append(cipher) }
        }

        guard let akmCount = readUInt16() else { return nil }
        var akms: [String] = []
        var fastTransition = false
        for _ in 0..<akmCount {
            guard offset + 4 <= data.count else { break }
            let oui = [data[offset], data[offset + 1], data[offset + 2]]
            let type = data[offset + 3]
            offset += 4
            let akmName = akmSuiteName(oui: oui, type: type)
            akms.append(akmName)
            if type == 3 || type == 4 || type == 9 {
                fastTransition = true
            }
        }

        var capabilities: [String] = []
        if offset + 2 <= data.count {
            let caps = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
            if (caps & 0x0001) != 0 { capabilities.append("PreAuth") }
            if (caps & 0x0002) != 0 { capabilities.append("No Pairwise") }
            let ptksa = (caps >> 2) & 0x3
            let gtksa = (caps >> 4) & 0x3
            if ptksa > 0 { capabilities.append("PTKSA Replay: \(ptksa)") }
            if gtksa > 0 { capabilities.append("GTKSA Replay: \(gtksa)") }
            let mfpr = (caps & 0x0040) != 0
            let mfpc = (caps & 0x0080) != 0
            if mfpc { capabilities.append("PMF Capable") }
            if mfpr { capabilities.append("PMF Required") }
        }

        let summary = "Group Cipher: \(groupCipher); Pairwise Cipher(s): \(pairwise.isEmpty ? "-" : pairwise.joined(separator: ", ")); AKM Suite(s): \(akms.isEmpty ? "-" : akms.joined(separator: ", "))"
        return RsnInfo(
            summary: summary,
            fastTransition: fastTransition,
            groupCipher: groupCipher,
            pairwise: pairwise,
            akms: akms,
            capabilities: capabilities
        )
    }

    private static func cipherSuiteName(oui: [UInt8], type: UInt8) -> String {
        let isStandard = oui == [0x00, 0x0F, 0xAC]
        if isStandard {
            switch type {
            case 1: return "WEP-40"
            case 2: return "TKIP"
            case 4: return "CCMP-128"
            case 5: return "WEP-104"
            case 8: return "GCMP-128"
            case 9: return "GCMP-256"
            case 10: return "CCMP-256"
            default: return "Unknown"
            }
        }
        return "Vendor"
    }

    private static func akmSuiteName(oui: [UInt8], type: UInt8) -> String {
        let isStandard = oui == [0x00, 0x0F, 0xAC]
        if isStandard {
            switch type {
            case 1: return "802.1X"
            case 2: return "PSK"
            case 3: return "FT 802.1X"
            case 4: return "FT PSK"
            case 5: return "802.1X SHA-256"
            case 6: return "PSK SHA-256"
            case 8: return "SAE"
            case 9: return "FT SAE"
            default: return "Unknown"
            }
        }
        return "Vendor"
    }

    private static func defaultElementName(for id: Int) -> String {
        switch id {
        case 11: return "BSS Load"
        case 50: return "Extended Supported Rates"
        case 42: return "ERP"
        default: return "Element \(id)"
        }
    }

    private static func hexString(_ data: Data, limit: Int = 64) -> String {
        let bytes = data.prefix(limit)
        let hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        if data.count > limit { return "\(hex) …" }
        return hex
    }

    private static func estimateBeaconAirtime(beaconInterval: Int?, beaconRate: Double?) -> Double? {
        guard let beaconInterval, beaconInterval > 0, let beaconRate, beaconRate > 0 else { return nil }
        let beaconSizeBytes = 300.0
        let airtimeMs = (beaconSizeBytes * 8.0) / (beaconRate * 1_000_000.0) * 1000.0
        let beaconsPerSecond = 1000.0 / Double(beaconInterval)
        let airtimePerSecondMs = airtimeMs * beaconsPerSecond
        return airtimePerSecondMs > 0 ? airtimePerSecondMs : nil
    }
}
