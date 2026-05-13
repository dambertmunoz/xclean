import Foundation

/// Cleans `~/Library/Caches/org.carthage.CarthageKit`. Generic cache — Carthage
/// repopulates it on the next `carthage update`.
struct CarthageCleaner: Cleaner {
    let id = "carthage"
    let title = "Carthage cache"

    func discover(config: RunConfig) throws -> [Candidate] {
        guard FS.exists(Paths.carthageCache) else { return [] }
        let size = FS.sizeOf(Paths.carthageCache)
        guard size > 0 else { return [] }
        return [
            Candidate(
                cleanerID: id,
                displayName: "Library/Caches/org.carthage.CarthageKit",
                sizeBytes: size,
                lastUsed: FS.lastModified(Paths.carthageCache),
                category: .generic,
                detail: "rebuilt by `carthage update`",
                removal: .path(Paths.carthageCache)
            )
        ]
    }
}
