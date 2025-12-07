import Foundation
import CoreWLAN
import ObjectiveC

class WiFiScanner {
    let interface = CWWiFiClient.shared().interface()
    private var networkCache: [String: (firstSeen: Date, lastSeen: Date)] = [:]
    
    func scan() -> [NetworkModel] {
        guard let networks = try? interface?.scanForNetworks(withSSID: nil) else { return [] }
        let now = Date()
        
        return networks.map { net in
            let channel = net.wlanChannel
            let securityValue = Self.decodeSecurity(net)
            let bssid = net.bssid ?? ""
            let vendor = OUIParser.vendor(for: bssid)
            
            // Получаем данные через reflection
            let mirror = Mirror(reflecting: net)
            let transmitRate = Self.getProperty(object: net, mirror: mirror, name: "transmitRate") as? Double
            let lastSeenDate = Self.getProperty(object: net, mirror: mirror, name: "lastSeen") as? Date
            
            // Вычисляем maxRate если не получен через reflection
            let generationStr = Self.generation(channel: channel)
            let channelWidthStr = Self.channelWidthString(channel)
            let calculatedMaxRate = Self.calculateMaxRate(generation: generationStr, channelWidth: channelWidthStr)
            let maxRate = transmitRate ?? calculatedMaxRate
            
            // Кэшируем firstSeen и lastSeen
            if networkCache[bssid] == nil {
                networkCache[bssid] = (firstSeen: now, lastSeen: now)
            } else {
                networkCache[bssid]?.lastSeen = lastSeenDate ?? now
            }
            let cached = networkCache[bssid]!
            
            // Вычисляем centerFrequency из channelNumber и band
            let centerFreq: Int? = {
                guard let ch = channel else { return nil }
                let num = ch.channelNumber
                switch ch.channelBand {
                case .band2GHz:
                    return 2407 + (num * 5) // Формула для 2.4GHz
                case .band5GHz:
                    return 5000 + (num * 5) // Формула для 5GHz
                case .band6GHz:
                    return 5940 + (num * 5) // Формула для 6GHz
                default:
                    return nil
                }
            }()
            
            // Получаем noise через noiseMeasurement
            let noiseValue = net.noiseMeasurement > 0 ? Int(net.noiseMeasurement) : nil
            let snrValue = noiseValue.map { Int(net.rssiValue) - $0 }
            
            // Вычисляем seen (секунды с последнего обнаружения)
            let seenSeconds = Int(abs(now.timeIntervalSince(cached.lastSeen)))
            
            // Получаем countryCode и deviceName через interface
            let countryCode = Self.getInterfaceProperty(name: "countryCode") as? String
            let deviceName = Self.getInterfaceProperty(name: "interfaceName") as? String
            
            // Пытаемся получить дополнительные данные через reflection
            let basicRates = Self.getProperty(object: net, mirror: mirror, name: "basicRates") as? [Double]
            let beaconInterval = Self.getProperty(object: net, mirror: mirror, name: "beaconInterval") as? Int
            let channelUtilization = Self.getProperty(object: net, mirror: mirror, name: "channelUtilization") as? Int
            let fastTransition = Self.getProperty(object: net, mirror: mirror, name: "fastTransition") as? Bool
            
            // Вычисляем minRate как часть от maxRate
            let minRate = Self.getProperty(object: net, mirror: mirror, name: "minRate") as? Double ?? (maxRate * 0.1)
            
            // Protection Mode выводим из security
            let protectionMode = Self.getProperty(object: net, mirror: mirror, name: "protectionMode") as? String ?? {
                switch securityValue {
                case "WPA3", "WPA2-Personal", "WPA2-Enterprise":
                    return "WPA2/WPA3"
                case "WPA-Personal", "WPA-Enterprise":
                    return "WPA"
                case "WEP":
                    return "WEP"
                default:
                    return "None"
                }
            }()
            
            let stations = Self.getProperty(object: net, mirror: mirror, name: "stations") as? Int
            
            // Вычисляем streams на основе generation
            let streams = Self.getProperty(object: net, mirror: mirror, name: "streams") as? Int ?? {
                switch generationStr {
                case "Wi-Fi 4": return 1
                case "Wi-Fi 5": return 2
                case "Wi-Fi 6", "Wi-Fi 6E": return 4
                default: return 1
                }
            }()
            
            // Type определяем из mode
            let type = Self.getProperty(object: net, mirror: mirror, name: "type") as? String ?? (net.ibss ? "Ad-hoc" : "Infrastructure")
            
            // WPS пытаемся определить через security (если WPA2 Personal, возможно есть WPS)
            let wps = Self.getProperty(object: net, mirror: mirror, name: "wps") as? String ?? {
                if securityValue.contains("WPA2-Personal") || securityValue.contains("WPA-Personal") {
                    return "Supported"
                }
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
    
    // Helper для получения свойств через Mirror и Objective-C runtime
    private static func getProperty(object: AnyObject, mirror: Mirror, name: String) -> Any? {
        // 1) Сначала пробуем через Mirror
        for child in mirror.children {
            if child.label == name {
                return child.value
            }
        }
        
        // 2) Пробуем через superclass mirror
        if let superMirror = mirror.superclassMirror {
            return getProperty(object: object, mirror: superMirror, name: name)
        }
        
        // 3) Пытаемся вызвать приватный селектор через Objective-C runtime
        // ВАЖНО: perform(_: ) безопасно только для методов, которые возвращают объект.
        // Много свойств CoreWLAN возвращают примитивы (UInt16/Int/Bool/Double). Вызов через
        // perform + takeUnretainedValue() приводит к интерпретации примитива как указателя,
        // что может упасть при значениях вроде 0x64 (100) — как в краше.
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector), let imp = object.method(for: selector) else {
            return nil
        }
        
        // Известные ключи с примитивным возвратом — вызываем типобезопасно через IMP
        switch name {
        case "beaconInterval", "channelUtilization", "stations", "streams":
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
            // Пытаемся трактовать как объектный возврат
            typealias Fn = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
            let fn = unsafeBitCast(imp, to: Fn.self)
            return fn(object, selector)?.takeUnretainedValue()
        }
    }
    
    // Helper для получения свойств interface
    private static func getInterfaceProperty(name: String) -> Any? {
        guard let interface = CWWiFiClient.shared().interface() else { return nil }
        let mirror = Mirror(reflecting: interface)
        return getProperty(object: interface, mirror: mirror, name: name)
    }
    
    // Вычисляем Max Rate на основе generation и channel width
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
        case "Wi-Fi 4":
            return 150.0 * widthMultiplier
        case "Wi-Fi 5":
            return 433.0 * widthMultiplier
        case "Wi-Fi 6", "Wi-Fi 6E":
            return 600.0 * widthMultiplier
        default:
            return 150.0 * widthMultiplier
        }
    }
    
    private static func decodeSecurity(_ net: CWNetwork) -> String {
        // Безопасно пытаемся получить приватное свойство через runtime, не используя KVC (которое может кидать исключение)
        let mirror = Mirror(reflecting: net)
        if let val = Self.getProperty(object: net, mirror: mirror, name: "security") as? CWSecurity {
            switch val {
            case .none: return "Open"
            case .dynamicWEP: return "WEP"
            case .wpaPersonal: return "WPA-Personal"
            case .wpa2Personal: return "WPA2-Personal"
            case .personal: return "Personal"
            case .wpaEnterprise: return "WPA-Enterprise"
            case .wpa2Enterprise: return "WPA2-Enterprise"
            case .enterprise: return "Enterprise"
            case .unknown: return "Unknown"
            @unknown default: return "Other"
            }
        }
        // Если доступа к полю нет — возвращаем дефолт
        return "-"
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
        if num >= 1 && num <= 14 {
            return "Wi-Fi 4"
        } else if num >= 36 && num <= 165 {
            return "Wi-Fi 5"
        } else if num >= 1 && num <= 233 {
            if num >= 1 && num <= 14 {
                return "Wi-Fi 4"
            } else if num >= 36 && num <= 96 {
                return "Wi-Fi 5"
            } else if num >= 100 && num <= 144 {
                return "Wi-Fi 6"
            } else if num >= 149 && num <= 233 {
                return "Wi-Fi 6E"
            }
        }
        return "Wi-Fi 6/6E"
    }
}
