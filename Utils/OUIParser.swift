import Foundation

struct OUIParser {
    static let ouiVendors: [String: String] = [
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
    
    static func vendor(for bssid: String) -> String {
        let key = bssid.uppercased().prefix(8)
        return ouiVendors[String(key)] ?? String(key)
    }
}
