import Foundation

struct OUIParser {
    // Базовый вшитый словарь на случай отсутствия внешней базы (ключи: AABBCC без двоеточий)
    static let builtIn: [String: String] = [
        "00:1A:2B": "Apple",
        "00:1B:63": "Cisco",
        "00:1D:D8": "ASUS",
        "00:0C:29": "VMware",
        "3C:5A:B4": "Samsung",
        "44:65:0D": "Netgear",
        "00:09:5B": "TP-Link",
        "F4:F5:D8": "Huawei",
        "00:1E:65": "Hewlett-Packard",
        "00:13:10": "Sony",
        "FC:FB:FB": "Xiaomi",
        "D8:50:E6": "LG Electronics",
        "C0:EE:FB": "D-Link",
        "F8:27:93": "Hon Hai Precision (Foxconn)",
        "00:25:9C": "Dell",
        "00:23:69": "AzureWave",
        "B8:27:EB": "Raspberry Pi Foundation",
        "28:37:37": "Intel",
        "3C:07:54": "Amazon Technologies",
        "20:76:93": "Realtek Semiconductor",
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
                for raw in text.split(separator: "\n") {
                    let line = String(raw).trimmingCharacters(in: .whitespacesAndNewlines)
                    if line.isEmpty { continue }
                    if line.hasPrefix("#") || line.hasPrefix("//") { continue }
                    if line.contains(",") {
                        // CSV: OUI,Vendor; OUI может быть с двоеточиями или без
                        let parts = line.split(separator: ",", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                        if parts.count == 2 {
                            let key = normalizeOui(parts[0])
                            if key.count == 6 { map[key] = parts[1] }
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
