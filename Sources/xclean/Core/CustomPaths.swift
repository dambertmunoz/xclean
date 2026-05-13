import Foundation

/// User-defined paths to inspect, layered on top of the curated registry.
///
/// File: `~/Library/Application Support/xclean/custom-paths.json`
/// Schema:
/// ```json
/// {
///   "paths": [
///     { "label": "Next build cache",
///       "path": "~/code/myapp/.next",
///       "category": "node",
///       "cleanup": "rm -rf $HOME/code/myapp/.next" }
///   ]
/// }
/// ```
/// `category` is matched against `InspectCategory.rawValue`; unknown values
/// silently fall back to "Other languages". `cleanup` and `note` are
/// optional. Tilde and `$HOME` expansion are applied to the path.
enum CustomPaths {

    private struct Document: Decodable {
        let paths: [Row]
    }
    private struct Row: Decodable {
        let label: String
        let path: String
        let category: String?
        let note: String?
        let cleanup: String?
        let dangerToTrash: Bool?
    }

    static var configURL: URL {
        IndexStore.defaultDirectory.appendingPathComponent("custom-paths.json")
    }

    /// Returns `[]` if the file is missing or malformed. We never throw —
    /// custom paths are a convenience layer, not a hard requirement.
    static func load() -> [InspectEntry] {
        guard let data = try? Data(contentsOf: configURL) else { return [] }
        guard let doc = try? JSONDecoder().decode(Document.self, from: data) else { return [] }
        return doc.paths.compactMap { row in
            let expanded = expand(row.path)
            let cat = matchCategory(row.category)
            return InspectEntry(
                label: row.label,
                path: URL(fileURLWithPath: expanded),
                category: cat,
                note: row.note,
                cleanup: row.cleanup,
                dangerToTrash: row.dangerToTrash ?? false
            )
        }
    }

    /// Writes an example doc the first time the menu's "Edit custom paths…"
    /// item is triggered, so the user has a template to fill in.
    static func ensureExampleExists() {
        guard !FileManager.default.fileExists(atPath: configURL.path) else { return }
        let example = """
        {
          "paths": [
            {
              "label": "Example: Next build cache",
              "path": "~/code/myapp/.next",
              "category": "node",
              "cleanup": "rm -rf $HOME/code/myapp/.next",
              "note": "delete me once you've configured your own paths"
            }
          ]
        }
        """
        try? FileManager.default.createDirectory(at: IndexStore.defaultDirectory, withIntermediateDirectories: true)
        try? example.data(using: .utf8)?.write(to: configURL, options: .atomic)
    }

    // MARK: - helpers

    private static func expand(_ s: String) -> String {
        var result = (s as NSString).expandingTildeInPath
        if let home = ProcessInfo.processInfo.environment["HOME"] {
            result = result.replacingOccurrences(of: "$HOME", with: home)
        }
        return result
    }

    private static func matchCategory(_ raw: String?) -> InspectCategory {
        guard let raw = raw?.lowercased() else { return .languages }
        for c in InspectCategory.allCases {
            if c.rawValue.lowercased() == raw { return c }
            if c.rawValue.lowercased().replacingOccurrences(of: " ", with: "") == raw.replacingOccurrences(of: " ", with: "") { return c }
        }
        return .languages
    }
}
