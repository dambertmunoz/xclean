import Foundation

/// Snapshot of the user's primary volume capacity. Uses the same numbers
/// Finder shows — `volumeAvailableCapacityForImportantUsageKey` accounts
/// for purgeable items and time-machine local snapshots the way macOS
/// recommends for "how much free space does the user really have".
struct DiskCapacity {
    let totalBytes: UInt64
    let availableBytes: UInt64

    var freeRatio: Double {
        guard totalBytes > 0 else { return 1 }
        return Double(availableBytes) / Double(totalBytes)
    }

    var usedBytes: UInt64 {
        totalBytes >= availableBytes ? totalBytes - availableBytes : 0
    }

    enum Health {
        case healthy   // >= 20% free
        case warning   // 10–20% free
        case critical  // < 10% free
    }

    var health: Health {
        let ratio = freeRatio
        if ratio < 0.10 { return .critical }
        if ratio < 0.20 { return .warning }
        return .healthy
    }
}

enum DiskInspector {
    /// Measures the volume that hosts the user's home directory.
    static func current() -> DiskCapacity? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity else {
            return nil
        }
        // `forImportantUsage` is the human-meaningful number (matches Finder).
        // It's an Int64 on macOS; cast through with a floor at 0.
        let available: Int64 = values.volumeAvailableCapacityForImportantUsage ?? 0
        let safeAvail = UInt64(max(0, available))
        return DiskCapacity(totalBytes: UInt64(total), availableBytes: safeAvail)
    }
}
