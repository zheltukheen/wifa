import Foundation

struct OUIParser {
    // Базовый вшитый словарь на случай отсутствия внешней базы (ключи: AABBCC без разделителей)
    static let builtIn: [String: String] = [
        "001A2B": "Apple",
        "001B63": "Cisco",
        "001DD8": "ASUS",
        "000C29": "VMware",
        "3C5AB4": "Samsung",
        "44650D": "Netgear",
        "00095B": "TP-Link",
        "F4F5D8": "Huawei",
        "001E65": "Hewlett-Packard",
        "001310": "Sony",
        "FCFBFB": "Xiaomi",
        "D850E6": "LG Electronics",
        "C0EEFB": "D-Link",
        "F82793": "Hon Hai Precision (Foxconn)",
        "00259C": "Dell",
        "002369": "AzureWave",
        "B827EB": "Raspberry Pi Foundation",
        "283737": "Intel",
        "3C0754": "Amazon Technologies",
        "207693": "Realtek Semiconductor",
    ]
    
    private static var cached: [String: String]? = nil
    
    /// Ленивая подгрузка базы OUI из bundle. Поддерживаем форматы:
    /// - "oui" или "oui.txt": строки вида "0023CE<TAB/SPACE>VENDOR NAME"
    /// - "oui.csv": строки вида "OUI,Vendor"
    private static func db() -> [String: String] {
        if let c = cached { return c }
        let candidates: [(name: String, ext: String?)] = [("oui", nil), ("oui", "txt"), ("oui", "csv"), ("OUI", nil), ("OUI", "txt"), ("OUI", "csv")]
        for cand in candidates {
            if let url = Bundle.main.url(forResource: cand.name, withExtension: cand.ext),
               let text = try? String(contentsOf: url) {
                var map: [String: String] = [:]
                let isCSV = (cand.ext?.lowercased() == "csv")
                for raw in text.split(separator: "\n") {
                    let line = String(raw).trimmingCharacters(in: .whitespacesAndNewlines)
                    if line.isEmpty { continue }
                    if line.hasPrefix("#") || line.hasPrefix("//") { continue }
                    if isCSV {
                        // CSV: OUI,Vendor; OUI может быть с двоеточиями или без
                        let parts = line.split(separator: ",", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                        if parts.count == 2 {
                            let key = normalizeOui(parts[0])
                            if key.count == 6 { map[key] = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
                        }
                    } else {
                        // Whitespace-separated: first token OUI (AABBCC), rest is vendor name
                        if let r = line.rangeOfCharacter(from: .whitespacesAndNewlines) {
                            let lhs = String(line[..<r.lowerBound])
                            let rhs = String(line[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                            let key = normalizeOui(lhs)
                            if !rhs.isEmpty, key.count == 6 { map[key] = rhs }
                        }
                    }
                }
                cached = map.isEmpty ? builtIn : map
                return cached!
            }
        }
        cached = builtIn
        return cached!
    }
    
    /// Нормализует строку с OUI ("AA:BB:CC" или "AABBCC" → "AABBCC").
    private static func normalizeOui(_ s: String) -> String {
        let up = s.uppercased()
        let cleaned = up.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "")
        return String(cleaned.prefix(6))
    }
    
    static func vendor(for bssid: String) -> String {
        let trimmed = bssid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "-" }
        let key = normalizeOui(trimmed)
        return db()[key] ?? "-"
    }
}
