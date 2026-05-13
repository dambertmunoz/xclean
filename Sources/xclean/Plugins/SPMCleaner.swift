import Foundation

/// Cleans `~/Library/Caches/org.swift.swiftpm`.
///
/// We split the cache by sub-folder so the report is granular:
/// * `repositories/` — clone mirror, generic cache (rebuilt on resolve)
/// * everything else (`security/`, `configuration/`) is left alone unless aged
struct SPMCleaner: Cleaner {
    let id = "spm"
    let title = "Swift Package Manager cache"

    func discover(config: RunConfig) throws -> [Candidate] {
        guard FS.exists(Paths.spmCache) else { return [] }

        var out: [Candidate] = []

        let repos = Paths.spmCache.appendingPathComponent("repositories")
        if FS.exists(repos) {
            let size = FS.sizeOf(repos)
            if size > 0 {
                out.append(Candidate(
                    cleanerID: id,
                    displayName: "swiftpm/repositories",
                    sizeBytes: size,
                    lastUsed: FS.lastModified(repos),
                    category: .generic,
                    detail: "rebuilt by `swift package resolve`",
                    removal: .path(repos)
                ))
            }
        }

        // Catch any other large stale folder (e.g. legacy "checkouts" at global level).
        for child in FS.directChildren(Paths.spmCache) where FS.isDirectory(child) {
            let name = child.lastPathComponent
            guard name != "repositories" else { continue }
            guard name != "security" && name != "configuration" else { continue }
            let mtime = FS.lastModified(child)
            guard let when = mtime else { continue }
            let days = Classifier.daysSince(when)
            guard days >= config.profile.ageThresholdDays else { continue }
            let size = FS.sizeOf(child)
            guard size > 0 else { continue }

            out.append(Candidate(
                cleanerID: id,
                displayName: "swiftpm/\(name)",
                sizeBytes: size,
                lastUsed: when,
                category: .age,
                detail: "untouched in \(days)d",
                removal: .path(child)
            ))
        }
        return out
    }
}
