import Foundation

/// Cleans `~/Library/Developer/Xcode/DerivedData/*`.
///
/// Heuristics:
/// * **orphan** — the workspace path recorded in `info.plist` no longer exists
/// * **age**    — not modified within the profile age threshold
struct DerivedDataCleaner: Cleaner {
    let id = "derived-data"
    let title = "Xcode DerivedData"

    func discover(config: RunConfig) throws -> [Candidate] {
        guard FS.exists(Paths.derivedData) else { return [] }

        var out: [Candidate] = []
        for child in FS.directChildren(Paths.derivedData) {
            // Skip the global module cache; it has its own plugin.
            if child.lastPathComponent == "ModuleCache.noindex" { continue }
            // Skip anything that doesn't look like a project folder.
            guard FS.isDirectory(child) else { continue }

            let size = FS.sizeOf(child)
            let mtime = FS.mostRecentChildMTime(child) ?? FS.lastModified(child)
            let workspace = readWorkspacePath(in: child)

            if let ws = workspace, !FS.exists(ws) {
                out.append(Candidate(
                    cleanerID: id,
                    displayName: child.lastPathComponent,
                    sizeBytes: size,
                    lastUsed: mtime,
                    category: .orphan,
                    detail: "workspace gone: \(ws.path)",
                    removal: .path(child)
                ))
                continue
            }

            out.append(Candidate(
                cleanerID: id,
                displayName: child.lastPathComponent,
                sizeBytes: size,
                lastUsed: mtime,
                category: .age,
                detail: workspace.map { "workspace: \($0.path)" } ?? "no workspace recorded",
                removal: .path(child)
            ))
        }
        return out
    }

    /// DerivedData/<Project>-<hash>/info.plist has a `WorkspacePath` key that
    /// points at the .xcodeproj or .xcworkspace it was built from.
    private func readWorkspacePath(in folder: URL) -> URL? {
        let plist = folder.appendingPathComponent("info.plist")
        guard let data = try? Data(contentsOf: plist) else { return nil }
        let parsed = try? PropertyListSerialization.propertyList(from: data, format: nil)
        guard let dict = parsed as? [String: Any] else { return nil }
        guard let path = dict["WorkspacePath"] as? String else { return nil }
        return URL(fileURLWithPath: path)
    }
}
