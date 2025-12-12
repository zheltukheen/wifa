//
//  WiFiScanner.swift
//

import Foundation
import CoreWLAN
import ObjectiveC

// MARK: - Error Handling
enum WiFiError: Error, LocalizedError {
    case interfaceNotFound
    case scanFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .interfaceNotFound:
            return "Wi-Fi Interface not found or Wi-Fi is turned off."
        case .scanFailed(let error):
            return "Scan failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Private API Accessor (Optimization & Clean Code)
/// Структура для работы с Objective-C Runtime.
/// Селекторы кэшируются статически, что исключает накладные расходы на NSSelectorFromString в циклах.
fileprivate struct CWPrivateAPI {
    
    // Кэширование селекторов (выполняется 1 раз при загрузке класса)
    // Внутри struct CWPrivateAPI

        // Кэширование селекторов
        struct Selectors {
            // ИСПОЛЬЗУЕМ NSSelectorFromString ЧТОБЫ УБРАТЬ ОШИБКИ КОМПИЛЯТОРА
            static let transmitRate = NSSelectorFromString("transmitRate")
            static let minRate = NSSelectorFromString("minRate")
            static let basicRates = NSSelectorFromString("basicRates")
            static let beaconInterval = NSSelectorFromString("beaconInterval")
            static let channelUtilization = NSSelectorFromString("channelUtilization")
            static let fastTransition = NSSelectorFromString("fastTransition")
            static let stations = NSSelectorFromString("stations")
            static let streams = NSSelectorFromString("streams")
            static let security = NSSelectorFromString("security")
            static let protectionMode = NSSelectorFromString("protectionMode")
            static let wps = NSSelectorFromString("wps")
            static let type = NSSelectorFromString("type")
            static let countryCode = NSSelectorFromString("countryCode")
            static let interfaceName = NSSelectorFromString("interfaceName")
            
            static let ieDataCandidates = [
                NSSelectorFromString("informationElementData"),
                NSSelectorFromString("informationElements"),
                NSSelectorFromString("beaconIEData")
            ]
        }
    
    // MARK: - Generic Runtime Getters
    
    /// Безопасное получение Double (Primitive)
    static func getDouble(_ target: AnyObject, selector: Selector) -> Double? {
        guard target.responds(to: selector), let imp = target.method(for: selector) else { return nil }
        typealias Function = @convention(c) (AnyObject, Selector) -> Double
        let function = unsafeBitCast(imp, to: Function.self)
        return function(target, selector)
    }
    
    /// Безопасное получение Int (Primitive)
    static func getInt(_ target: AnyObject, selector: Selector) -> Int? {
        guard target.responds(to: selector), let imp = target.method(for: selector) else { return nil }
        typealias Function = @convention(c) (AnyObject, Selector) -> Int
        let function = unsafeBitCast(imp, to: Function.self)
        return function(target, selector)
    }
    
    /// Безопасное получение Bool (Primitive)
    static func getBool(_ target: AnyObject, selector: Selector) -> Bool? {
        guard target.responds(to: selector), let imp = target.method(for: selector) else { return nil }
        // В ObjC bool это часто char, но ObjCBool надежнее
        typealias Function = @convention(c) (AnyObject, Selector) -> ObjCBool
        let function = unsafeBitCast(imp, to: Function.self)
        return function(target, selector).boolValue
    }
    
    /// Безопасное получение Object (String, Array, etc)
    static func getObject<T>(_ target: AnyObject, selector: Selector) -> T? {
        guard target.responds(to: selector) else { return nil }
        // performSelector возвращает Unmanaged<AnyObject>
        return target.perform(selector)?.takeUnretainedValue() as? T
    }
    
    /// Поиск IE Data по списку кандидатов
    static func getIEData(_ target: AnyObject) -> Data? {
        for sel in Selectors.ieDataCandidates {
            if let data: Data = getObject(target, selector: sel) {
                return data
            }
        }
        return nil
    }
}

// MARK: - WiFi Scanner Actor
/// Actor гарантирует потокобезопасность состояния (networkCache) без использования NSLock.
actor WiFiScanner {
    
    private let client = CWWiFiClient.shared()
    
    // Кэш изолирован внутри актора. Data Race невозможен.
    private var networkCache: [String: (firstSeen: Date, lastSeen: Date)] = [:]
    
    /// Асинхронное сканирование.
    /// Не блокирует вызывающий поток (UI), так как выполняется внутри Task/Actor infrastructure.
    func scan() async throws -> [NetworkModel] {
        guard let interface = client.interface() else {
            throw WiFiError.interfaceNotFound
        }
        
        // Scan operation (Blocking IO wrapped in async)
        // CWWiFiClient scan is synchronous, so we assume the actor execution context handles the suspension point,
        // strictly speaking CoreWLAN scan blocks the thread it runs on.
        // In a real heavy app, you might want to wrap this specific line in Task.detached if it blocks the Main Actor too much,
        // but since this is a separate Actor, it won't block the Main Thread (UI).
        let networks: Set<CWNetwork>
        do {
             networks = try interface.scanForNetworks(withSSID: nil)
        } catch {
            throw WiFiError.scanFailed(error)
        }
        
        let now = Date()
        
        // Получаем свойства интерфейса один раз
        let countryCode: String? = CWPrivateAPI.getObject(interface, selector: CWPrivateAPI.Selectors.countryCode)
        let deviceName: String? = CWPrivateAPI.getObject(interface, selector: CWPrivateAPI.Selectors.interfaceName)
        
        // Обработка результатов
        var resultModels: [NetworkModel] = []
        resultModels.reserveCapacity(networks.count)
        
        for net in networks {
            let bssid = net.bssid ?? ""
            let ssid = net.ssid ?? ""
            let channel = net.wlanChannel
            
            // --- Cache Update (Actor Protected) ---
            if let cached = networkCache[bssid] {
                networkCache[bssid] = (cached.firstSeen, now)
            } else {
                networkCache[bssid] = (now, now)
            }
            let timestamps = networkCache[bssid]!
            
            // --- Private / Runtime Data Extraction ---
            
            // 1. Rates
            let transmitRate = CWPrivateAPI.getDouble(net, selector: CWPrivateAPI.Selectors.transmitRate)
            
            // Вычисляем MaxRate, если система не вернула
            let genStr = WiFiLogic.generation(channel: channel)
            let widthStr = WiFiLogic.channelWidthString(channel)
            let calculatedMax = WiFiLogic.calculateMaxRate(generation: genStr, channelWidth: widthStr)
            let maxRate = transmitRate ?? calculatedMax
            
            let minRate = CWPrivateAPI.getDouble(net, selector: CWPrivateAPI.Selectors.minRate) ?? (maxRate * 0.1)
            
            // 2. IE Parsing (Deep Packet Inspection)
            var basicRates: [Double]? = CWPrivateAPI.getObject(net, selector: CWPrivateAPI.Selectors.basicRates)
            var channelUtil: Int? = CWPrivateAPI.getInt(net, selector: CWPrivateAPI.Selectors.channelUtilization)
            var fastTransition: Bool? = CWPrivateAPI.getBool(net, selector: CWPrivateAPI.Selectors.fastTransition)
            var stations: Int? = CWPrivateAPI.getInt(net, selector: CWPrivateAPI.Selectors.stations)
            
            if let ieData = CWPrivateAPI.getIEData(net) {
                let parsed = IEParser.parse(ieData)
                if basicRates == nil { basicRates = parsed.basicRates }
                if channelUtil == nil { channelUtil = parsed.channelUtilization }
                if fastTransition == nil { fastTransition = parsed.fastTransition }
                if stations == nil { stations = parsed.stations }
            }
            
            // 3. Security & Other Properties
            let securityValue = WiFiLogic.decodeSecurity(net)
            let protectionMode: String = CWPrivateAPI.getObject(net, selector: CWPrivateAPI.Selectors.protectionMode) ?? {
                if securityValue.contains("WPA3") { return "WPA3" }
                if securityValue.contains("WPA2") { return "WPA2" }
                return "None"
            }()
            
            let wps: String = CWPrivateAPI.getObject(net, selector: CWPrivateAPI.Selectors.wps) ?? (securityValue.contains("Personal") ? "Supported" : "Unknown")
            
            let streams = CWPrivateAPI.getInt(net, selector: CWPrivateAPI.Selectors.streams) ?? WiFiLogic.defaultStreams(for: genStr)
            let type: String = CWPrivateAPI.getObject(net, selector: CWPrivateAPI.Selectors.type) ?? (net.ibss ? "Ad-hoc" : "Infrastructure")
            
            // 4. Calculations
            let noise = net.noiseMeasurement != 0 ? Int(net.noiseMeasurement) : nil
            let snr = noise.map { Int(net.rssiValue) - $0 }
            let seenSeconds = Int(now.timeIntervalSince(timestamps.lastSeen))
            
            // 5. Model Assembly
            let model = NetworkModel(
                bssid: bssid,
                band: WiFiLogic.bandString(channel),
                channel: Int(channel?.channelNumber ?? 0),
                channelWidth: widthStr,
                generation: genStr,
                maxRate: maxRate,
                mode: net.ibss ? "IBSS" : "Station",
                ssid: ssid,
                security: securityValue,
                seen: seenSeconds,
                signal: net.rssiValue,
                vendor: OUIParser.vendor(for: bssid), // Предполагается наличие Utils/OUIParser
                basicRates: basicRates,
                beaconInterval: CWPrivateAPI.getInt(net, selector: CWPrivateAPI.Selectors.beaconInterval),
                centerFrequency: WiFiLogic.centerFreq(channel),
                channelUtilization: channelUtil,
                countryCode: countryCode,
                deviceName: deviceName,
                fastTransition: fastTransition,
                firstSeen: timestamps.firstSeen,
                lastSeen: timestamps.lastSeen,
                minRate: minRate,
                noise: noise,
                protectionMode: protectionMode,
                snr: snr,
                stations: stations,
                streams: streams,
                type: type,
                wps: wps
            )
            resultModels.append(model)
        }
        
        return resultModels
    }
}

// MARK: - WiFi Logic Helpers (Pure Functions)
/// Вынесена чистая логика преобразований
fileprivate struct WiFiLogic {
    static func bandString(_ channel: CWChannel?) -> String {
        guard let ch = channel else { return "-" }
        switch ch.channelBand {
        case .band2GHz: return "2.4GHz"
        case .band5GHz: return "5GHz"
        case .band6GHz: return "6GHz"
        default: return "-"
        }
    }
    
    static func channelWidthString(_ channel: CWChannel?) -> String {
        guard let cw = channel else { return "-" }
        switch cw.channelWidth {
        case .width20MHz: return "20MHz"
        case .width40MHz: return "40MHz"
        case .width80MHz: return "80MHz"
        case .width160MHz: return "160MHz"
        default: return "-"
        }
    }
    
    static func generation(channel: CWChannel?) -> String {
        guard let ch = channel else { return "-" }
        let num = ch.channelNumber
        if num >= 1 && num <= 14 { return "Wi-Fi 4" }
        else if num >= 36 && num <= 165 { return "Wi-Fi 5" }
        else if num > 165 { return "Wi-Fi 6E" }
        return "Wi-Fi 4/5/6"
    }
    
    static func centerFreq(_ channel: CWChannel?) -> Int? {
        guard let ch = channel else { return nil }
        let num = ch.channelNumber
        switch ch.channelBand {
        case .band2GHz: return 2407 + (num * 5)
        case .band5GHz: return 5000 + (num * 5)
        case .band6GHz: return 5940 + (num * 5)
        default: return nil
        }
    }
    
    static func calculateMaxRate(generation: String, channelWidth: String) -> Double {
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
    
    static func defaultStreams(for generation: String) -> Int {
        switch generation {
        case "Wi-Fi 4": return 1
        case "Wi-Fi 5": return 2
        case "Wi-Fi 6", "Wi-Fi 6E": return 4
        default: return 1
        }
    }
    
    static func decodeSecurity(_ net: CWNetwork) -> String {
        // Попытка через приватный API (int value)
        if let raw = CWPrivateAPI.getInt(net, selector: CWPrivateAPI.Selectors.security) {
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
            default: break
            }
        }
        
        // Public API Fallback
        if net.supportsSecurity(.wpa2Personal) { return "WPA2-Personal" }
        if net.supportsSecurity(.wpaPersonal) { return "WPA-Personal" }
        if net.supportsSecurity(.dynamicWEP) { return "WEP" }
        if net.supportsSecurity(.none) { return "Open" }
        
        return "Unknown"
    }
}

// MARK: - IE Parser
/// Парсер Information Elements из сырых байтов
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
            
            // Используем ArraySlice для zero-copy где возможно, но здесь создаем массив для безопасности
            let payload = bytes[idx..<(idx+len)]
            idx += len
            
            switch id {
            case 1, 50: // Supported Rates / Extended Supported Rates
                let rates = payload.map { Double($0 & 0x7F) * 0.5 }
                if result.basicRates == nil {
                    // Ищем Basic Rates (бит 0x80)
                    let basic = payload.enumerated().compactMap { (_, b) -> Double? in
                        (b & 0x80) != 0 ? Double(b & 0x7F) * 0.5 : nil
                    }
                    result.basicRates = basic.isEmpty ? rates : basic
                } else {
                    result.basicRates?.append(contentsOf: rates)
                }
                
            case 11: // QBSS Load
                if payload.count >= 3 {
                    // Station Count (2 bytes)
                    let staCount = UInt16(payload[payload.startIndex]) | (UInt16(payload[payload.startIndex + 1]) << 8)
                    result.stations = Int(staCount)
                    // Channel Utilization (1 byte)
                    result.channelUtilization = Int(payload[payload.startIndex + 2])
                }
                
            case 48: // RSN (WPA2/3)
                // Очень упрощенный парсинг для поиска FT (Fast Transition)
                if payload.count >= 8 {
                    // Пропускаем Version (2) + Group Cipher (4)
                    var p = payload.startIndex + 6
                    
                    // Pairwise Cipher Count
                    guard p + 2 <= payload.endIndex else { break }
                    let pcCount = Int(UInt16(payload[p]) | (UInt16(payload[p+1]) << 8))
                    p += 2
                    p += (4 * pcCount) // Пропускаем Pairwise Ciphers
                    
                    // AKM Suite Count
                    guard p + 2 <= payload.endIndex else { break }
                    let akmCount = Int(UInt16(payload[p]) | (UInt16(payload[p+1]) << 8))
                    p += 2
                    
                    for _ in 0..<akmCount {
                        guard p + 4 <= payload.endIndex else { break }
                        let oui = (payload[p], payload[p+1], payload[p+2])
                        let type = payload[p+3]
                        p += 4
                        
                        // 00-0F-AC (Apple/Standard) type 3 (FT-802.1X) or 4 (FT-PSK)
                        if oui == (0x00, 0x0F, 0xAC) {
                            if type == 3 || type == 4 {
                                result.fastTransition = true
                            }
                        }
                    }
                }
                
            default: break
            }
        }
        return result
    }
}
