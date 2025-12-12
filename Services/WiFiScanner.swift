import Foundation
import CoreWLAN
import ObjectiveC

class WiFiScanner {
    // Используем computed property, так как интерфейс может меняться (вкл/выкл Wi-Fi)
    private var client: CWWiFiClient? { CWWiFiClient.shared() }
    
    // Блокировка для потокобезопасности кэша (предотвращает Data Race)
    private let cacheLock = NSLock()
    private var networkCache: [String: (firstSeen: Date, lastSeen: Date)] = [:]
    
    func scan() -> [NetworkModel] {
        // Проверяем наличие интерфейса
        guard let interface = client?.interface() else {
            print("WiFiScanner Error: Wi-Fi Interface not found (Wi-Fi might be off)")
            return []
        }
        
        // Сканируем с обработкой ошибок (важно для отладки прав доступа в Release)
        var networks: Set<CWNetwork> = []
        do {
            networks = try interface.scanForNetworks(withSSID: nil)
        } catch {
            print("WiFiScanner Critical Error: \(error.localizedDescription)")
            // Если ошибка "Location Manager error", значит нет прав в Info.plist или App Sandbox
            return []
        }
        
        let now = Date()
        
        return networks.map { net in
            let channel = net.wlanChannel
            // Декодируем безопасность через Int, чтобы избежать ошибок компиляции с отсутствующими enum cases
            let securityValue = Self.decodeSecurity(net)
            let bssid = net.bssid ?? ""
            // OUIParser должен быть реализован в проекте (Utils/OUIParser.swift)
            let vendor = OUIParser.vendor(for: bssid)
            
            // --- Reflection & Runtime Magic ---
            let mirror = Mirror(reflecting: net)
            
            // Пытаемся достать приватные свойства
            let transmitRate = Self.getProperty(object: net, mirror: mirror, name: "transmitRate") as? Double
            let lastSeenDate = Self.getProperty(object: net, mirror: mirror, name: "lastSeen") as? Date
            
            // Вычисляем maxRate (если система не отдала transmitRate)
            let generationStr = Self.generation(channel: channel)
            let channelWidthStr = Self.channelWidthString(channel)
            let calculatedMaxRate = Self.calculateMaxRate(generation: generationStr, channelWidth: channelWidthStr)
            let maxRate = transmitRate ?? calculatedMaxRate
            
            // --- Caching Logic ---
            cacheLock.lock()
            if networkCache[bssid] == nil {
                networkCache[bssid] = (firstSeen: now, lastSeen: now)
            } else {
                // Если система вернула lastSeen, используем его, иначе текущее время
                networkCache[bssid]?.lastSeen = lastSeenDate ?? now
            }
            let cached = networkCache[bssid]!
            cacheLock.unlock()
            
            // --- Data Processing ---
            
            // Центральная частота (приблизительно)
            let centerFreq: Int? = {
                guard let ch = channel else { return nil }
                let num = ch.channelNumber
                switch ch.channelBand {
                case .band2GHz: return 2407 + (num * 5)
                case .band5GHz: return 5000 + (num * 5)
                case .band6GHz: return 5940 + (num * 5)
                default: return nil
                }
            }()
            
            // Шум и SNR
            let noiseRaw = net.noiseMeasurement
            let noiseValue = noiseRaw != 0 ? Int(noiseRaw) : nil
            let snrValue = noiseValue.map { Int(net.rssiValue) - $0 }
            
            // Время с последнего контакта
            let seenSeconds = Int(abs(now.timeIntervalSince(cached.lastSeen)))
            
            // Свойства интерфейса (Country Code)
            let countryCode = Self.getInterfaceProperty(name: "countryCode") as? String
            let deviceName = Self.getInterfaceProperty(name: "interfaceName") as? String
            
            // Приватные метрики
            var basicRates = Self.getProperty(object: net, mirror: mirror, name: "basicRates") as? [Double]
            let beaconInterval = Self.getProperty(object: net, mirror: mirror, name: "beaconInterval") as? Int
            var channelUtilization = Self.getProperty(object: net, mirror: mirror, name: "channelUtilization") as? Int
            var fastTransition = Self.getProperty(object: net, mirror: mirror, name: "fastTransition") as? Bool
            
            // --- IE Parsing (Deep Packet Inspection) ---
            // Если CoreWLAN скрывает данные, достаем их из сырых байтов
            if let ieData = Self.getInformationElements(from: net, mirror: mirror) {
                let parsed = IEParser.parse(ieData)
                if basicRates == nil { basicRates = parsed.basicRates }
                if channelUtilization == nil { channelUtilization = parsed.channelUtilization }
                if fastTransition == nil { fastTransition = parsed.fastTransition }
            }
            
            let minRate = Self.getProperty(object: net, mirror: mirror, name: "minRate") as? Double ?? (maxRate * 0.1)
            
            // Упрощение отображения защиты
            let protectionMode = Self.getProperty(object: net, mirror: mirror, name: "protectionMode") as? String ?? {
                if securityValue.contains("WPA3") { return "WPA3" }
                if securityValue.contains("WPA2") { return "WPA2" }
                if securityValue.contains("WPA") { return "WPA" }
                if securityValue.contains("WEP") { return "WEP" }
                return "None"
            }()
            
            let stationsRuntime = Self.getProperty(object: net, mirror: mirror, name: "stations") as? Int
            let stations = stationsRuntime ?? IEParser.parse(Self.getInformationElements(from: net, mirror: mirror) ?? Data()).stations
            
            let streams = Self.getProperty(object: net, mirror: mirror, name: "streams") as? Int ?? {
                switch generationStr {
                case "Wi-Fi 4": return 1
                case "Wi-Fi 5": return 2
                case "Wi-Fi 6", "Wi-Fi 6E": return 4
                default: return 1
                }
            }()
            
            let type = Self.getProperty(object: net, mirror: mirror, name: "type") as? String ?? (net.ibss ? "Ad-hoc" : "Infrastructure")
            
            let wps = Self.getProperty(object: net, mirror: mirror, name: "wps") as? String ?? {
                if securityValue.contains("Personal") { return "Supported" }
                return "Unknown"
            }()
            
            return NetworkModel(
                bssid: bssid,
                band: Self.bandString(channel),
                channel: Int(channel?.channelNumber ?? 0),
                channelWidth: Self.channelWidthString(channel),
                generation: Self.generation(channel: channel),
                maxRate: maxRate,
                mode: net.ibss ? "IBSS" : "Station",
                ssid: net.ssid ?? "",
                security: securityValue,
                seen: seenSeconds,
                signal: net.rssiValue,
                vendor: vendor,
                basicRates: basicRates,
                beaconInterval: beaconInterval,
                centerFrequency: centerFreq,
                channelUtilization: channelUtilization,
                countryCode: countryCode,
                deviceName: deviceName,
                fastTransition: fastTransition,
                firstSeen: cached.firstSeen,
                lastSeen: lastSeenDate ?? cached.lastSeen,
                minRate: minRate,
                noise: noiseValue,
                protectionMode: protectionMode,
                snr: snrValue,
                stations: stations,
                streams: streams,
                type: type,
                wps: wps
            )
        }
    }
    
    // MARK: - Safe Runtime Access
    
    private static func getProperty(object: AnyObject, mirror: Mirror, name: String) -> Any? {
        // 1. Пробуем через Swift Mirror (безопасно)
        for child in mirror.children {
            if child.label == name { return child.value }
        }
        if let superMirror = mirror.superclassMirror {
            return getProperty(object: object, mirror: superMirror, name: name)
        }
        
        // 2. Пробуем через ObjC Runtime (опасно для примитивов, используем защиту)
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector), let imp = object.method(for: selector) else {
            return nil
        }
        
        // ВАЖНО: Для примитивных типов (Int, Bool, Double) нельзя использовать performSelector,
        // так как он возвращает указатель, а не значение. Используем unsafeBitCast для вызова по сигнатуре.
        switch name {
        case "beaconInterval", "channelUtilization", "stations", "streams", "security":
            typealias Fn = @convention(c) (AnyObject, Selector) -> Int
            let fn = unsafeBitCast(imp, to: Fn.self)
            return fn(object, selector)
        case "fastTransition":
            typealias Fn = @convention(c) (AnyObject, Selector) -> ObjCBool
            let fn = unsafeBitCast(imp, to: Fn.self)
            return fn(object, selector).boolValue
        case "transmitRate", "minRate":
            typealias Fn = @convention(c) (AnyObject, Selector) -> Double
            let fn = unsafeBitCast(imp, to: Fn.self)
            return fn(object, selector)
        default:
            // Для объектов (String, Date, Data)
            typealias Fn = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
            let fn = unsafeBitCast(imp, to: Fn.self)
            return fn(object, selector)?.takeUnretainedValue()
        }
    }
    
    private static func getInterfaceProperty(name: String) -> Any? {
        guard let interface = CWWiFiClient.shared().interface() else { return nil }
        let mirror = Mirror(reflecting: interface)
        return getProperty(object: interface, mirror: mirror, name: name)
    }
    
    private static func calculateMaxRate(generation: String, channelWidth: String) -> Double {
        let widthMultiplier: Double = {
            switch channelWidth {
            case "20MHz": return 1.0
            case "40MHz": return 2.0
            case "80MHz": return 4.0
            case "160MHz": return 8.0
            default: return 1.0
            }
        }()
        
        switch generation {
        case "Wi-Fi 4": return 150.0 * widthMultiplier
        case "Wi-Fi 5": return 433.0 * widthMultiplier
        case "Wi-Fi 6", "Wi-Fi 6E": return 600.0 * widthMultiplier
        default: return 150.0 * widthMultiplier
        }
    }
    
    private static func decodeSecurity(_ net: CWNetwork) -> String {
        let mirror = Mirror(reflecting: net)
        
        // Используем сырое значение Int, чтобы не зависеть от версии SDK
        if let raw = Self.getProperty(object: net, mirror: mirror, name: "security") as? Int {
            switch raw {
            case 0: return "Open"
            case 1: return "WEP"
            case 2: return "WPA-Personal"
            case 3: return "WPA/WPA2-Personal Mixed"
            case 4: return "WPA-Enterprise"
            case 5: return "WPA/WPA2-Enterprise Mixed"
            case 6: return "WPA2-Personal"
            case 7: return "WPA2-Enterprise"
            case 8: return "Dynamic WEP"
            case 9: return "WPA3-Personal"
            case 10: return "WPA3-Enterprise"
            case 11: return "WPA3-Transition"
            case 12: return "OWE"
            case 13: return "OWE-Transition"
            default: return "Unknown (\(raw))"
            }
        }
        
        // Fallback на публичные методы
        if net.supportsSecurity(.wpa2Personal) { return "WPA2-Personal" }
        if net.supportsSecurity(.wpaPersonal) { return "WPA-Personal" }
        if net.supportsSecurity(.dynamicWEP) { return "WEP" }
        if net.supportsSecurity(.none) { return "Open" }
        
        return "Unknown"
    }
    
    private static func bandString(_ channel: CWChannel?) -> String {
        guard let ch = channel else { return "-" }
        switch ch.channelBand {
        case .band2GHz: return "2.4GHz"
        case .band5GHz: return "5GHz"
        case .band6GHz: return "6GHz"
        default: return "-"
        }
    }
    
    private static func channelWidthString(_ channel: CWChannel?) -> String {
        guard let cw = channel else { return "-" }
        switch cw.channelWidth {
        case .width20MHz: return "20MHz"
        case .width40MHz: return "40MHz"
        case .width80MHz: return "80MHz"
        case .width160MHz: return "160MHz"
        default: return "-"
        }
    }
    
    private static func generation(channel: CWChannel?) -> String {
        guard let ch = channel else { return "-" }
        let num = ch.channelNumber
        
        if num >= 1 && num <= 14 { return "Wi-Fi 4" }
        else if num >= 36 && num <= 165 { return "Wi-Fi 5" }
        else if num > 165 { return "Wi-Fi 6E" }
        
        return "Wi-Fi 4/5/6"
    }
    
    private static func getInformationElements(from object: AnyObject, mirror: Mirror) -> Data? {
        let candidates = [
            "informationElementData", "informationElements", "informationElement",
            "ieData", "IEData", "IE", "ies", "beaconIEData", "beaconIE", "beaconIEs"
        ]
        for name in candidates {
            if let any = getProperty(object: object, mirror: mirror, name: name) {
                if let d = any as? Data { return d }
                if let nd = any as? NSData { return nd as Data }
            }
        }
        return nil
    }
}

// MARK: - IE Parser (Для извлечения скрытых данных)
struct IEParser {
    struct Parsed {
        var basicRates: [Double]? = nil
        var channelUtilization: Int? = nil
        var stations: Int? = nil
        var fastTransition: Bool? = nil
    }
    
    static func parse(_ data: Data) -> Parsed {
        var result = Parsed()
        var idx = 0
        let bytes = [UInt8](data)
        while idx + 2 <= bytes.count {
            let id = Int(bytes[idx]); idx += 1
            let len = Int(bytes[idx]); idx += 1
            guard idx + len <= bytes.count else { break }
            let payload = Array(bytes[idx..<(idx+len)])
            idx += len
            switch id {
            case 1, 50: // Supported Rates
                let rates = payload.map { Double($0 & 0x7F) * 0.5 }
                if result.basicRates == nil {
                    let basic = payload.enumerated().compactMap { (_, b) -> Double? in
                        (b & 0x80) != 0 ? Double(b & 0x7F) * 0.5 : nil
                    }
                    result.basicRates = basic.isEmpty ? rates : basic
                } else {
                    result.basicRates = (result.basicRates ?? []) + rates
                }
            case 11: // BSS Load
                if payload.count >= 3 {
                    result.stations = Int(UInt16(payload[0]) | (UInt16(payload[1]) << 8))
                    result.channelUtilization = Int(payload[2])
                }
            case 48: // RSN
                if payload.count >= 10 {
                    var p = 0
                    func take(_ n: Int) -> [UInt8]? {
                        guard p + n <= payload.count else { return nil }
                        let out = Array(payload[p..<(p+n)]); p += n; return out
                    }
                    _ = take(6) // Ver + Group Cipher
                    guard let pcBytes = take(2) else { break }
                    let pc = Int(UInt16(pcBytes[0]) | (UInt16(pcBytes[1]) << 8))
                    _ = take(4 * pc) // Pairwise Ciphers
                    guard let akmCountBytes = take(2) else { break }
                    let akmCount = Int(UInt16(akmCountBytes[0]) | (UInt16(akmCountBytes[1]) << 8))
                    for _ in 0..<akmCount {
                        guard let akm = take(4) else { break }
                        if akm[0] == 0x00 && akm[1] == 0x0F && akm[2] == 0xAC {
                            if akm[3] == 3 || akm[3] == 4 { result.fastTransition = true }
                        }
                    }
                }
            default: break
            }
        }
        return result
    }
}
