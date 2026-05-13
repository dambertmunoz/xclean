import Foundation

/// Cleans `~/Library/Developer/Xcode/Archives/YYYY-MM-DD/*.xcarchive`.
///
/// Only emits candidates when the profile permits touching Archives — these
/// may contain signed App Store submissions, so the bar is intentionally high.
struct ArchivesCleaner: Cleaner {
    let id = "archives"
    let title = "Xcode Archives"

    func discover(config: RunConfig) throws -> [Candidate] {
        guard config.profile.touchesArchives else { return [] }
        guard FS.exists(Paths.archives) else { return [] }

        var out: [Candidate] = []
        for dateFolder in FS.directChildren(Paths.archives) where FS.isDirectory(dateFolder) {
            for archive in FS.directChildren(dateFolder) where archive.pathExtension == "xcarchive" {
                let mtime = FS.lastModified(archive) ?? FS.lastModified(dateFolder)
                guard let when = mtime else { continue }
                let days = Classifier.daysSince(when)
                guard days >= config.profile.archivesAgeDays else { continue }

                let size = FS.sizeOf(archive)
                out.append(Candidate(
                    cleanerID: id,
                    displayName: "\(dateFolder.lastPathComponent)/\(archive.lastPathComponent)",
                    sizeBytes: size,
                    lastUsed: when,
                    category: .age,
                    detail: "archive \(days)d old, threshold \(config.profile.archivesAgeDays)d",
                    removal: .path(archive)
                ))
            }
        }
        return out
    }
}
