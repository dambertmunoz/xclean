import Foundation

/// Cleans `~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex`.
/// This cache is rebuilt on next compile, so it is always safe to drop.
struct ModuleCacheCleaner: Cleaner {
    let id = "module-cache"
    let title = "Xcode Module Cache"

    func discover(config: RunConfig) throws -> [Candidate] {
        guard FS.exists(Paths.moduleCache) else { return [] }
        let size = FS.sizeOf(Paths.moduleCache)
        guard size > 0 else { return [] }
        return [
            Candidate(
                cleanerID: id,
                displayName: "ModuleCache.noindex",
                sizeBytes: size,
                lastUsed: FS.lastModified(Paths.moduleCache),
                category: .generic,
                detail: "rebuilt on next compile",
                removal: .path(Paths.moduleCache)
            )
        ]
    }
}
