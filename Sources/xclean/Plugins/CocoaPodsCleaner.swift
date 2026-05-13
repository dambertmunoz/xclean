import Foundation

/// Cleans `~/Library/Caches/CocoaPods`. Treated as a single generic cache —
/// CocoaPods rebuilds it on the next `pod install`.
struct CocoaPodsCleaner: Cleaner {
    let id = "cocoapods"
    let title = "CocoaPods cache"

    func discover(config: RunConfig) throws -> [Candidate] {
        guard config.profile.touchesCocoaPodsCache else { return [] }
        guard FS.exists(Paths.cocoaPodsCache) else { return [] }
        let size = FS.sizeOf(Paths.cocoaPodsCache)
        guard size > 0 else { return [] }
        return [
            Candidate(
                cleanerID: id,
                displayName: "Library/Caches/CocoaPods",
                sizeBytes: size,
                lastUsed: FS.lastModified(Paths.cocoaPodsCache),
                category: .generic,
                detail: "rebuilt by `pod install`",
                removal: .path(Paths.cocoaPodsCache)
            )
        ]
    }
}
