import Foundation

enum ByteSize {
    static func human(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var value = Double(bytes)
        var unit = 0
        while value >= 1024 && unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        if unit == 0 {
            return "\(Int(value)) \(units[unit])"
        }
        return String(format: "%.2f %@", value, units[unit])
    }
}
