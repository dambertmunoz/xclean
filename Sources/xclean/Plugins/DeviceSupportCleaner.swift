import Foundation

/// Cleans iOS / watchOS / tvOS DeviceSupport bundles.
///
/// Heuristic: each platform keeps only the `profile.keepDeviceSupports` newest
/// entries (by directory mtime). Older entries are emitted as `.duplicate`.
struct DeviceSupportCleaner: Cleaner {
    let id = "device-support"
    let title = "Device Support (iOS / watchOS / tvOS)"

    private let roots: [(label: String, url: URL)] = [
        ("iOS",     Paths.iOSDeviceSupport),
        ("watchOS", Paths.watchOSDeviceSupport),
        ("tvOS",    Paths.tvOSDeviceSupport)
    ]

    func discover(config: RunConfig) throws -> [Candidate] {
        var out: [Candidate] = []
        let keep = max(0, config.profile.keepDeviceSupports)

        for root in roots {
            guard FS.exists(root.url) else { continue }
            let entries = FS.directChildren(root.url)
                .filter { FS.isDirectory($0) }
                .map { (url: $0, mtime: FS.lastModified($0) ?? .distantPast) }
                .sorted { $0.mtime > $1.mtime } // newest first

            guard entries.count > keep else { continue }
            for entry in entries.dropFirst(keep) {
                let size = FS.sizeOf(entry.url)
                out.append(Candidate(
                    cleanerID: id,
                    displayName: "\(root.label) — \(entry.url.lastPathComponent)",
                    sizeBytes: size,
                    lastUsed: entry.mtime == .distantPast ? nil : entry.mtime,
                    category: .duplicate,
                    detail: "keeping newest \(keep) \(root.label) device support bundles",
                    removal: .path(entry.url)
                ))
            }
        }
        return out
    }
}
