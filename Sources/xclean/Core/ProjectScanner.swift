import Foundation

/// Walks well-known project roots looking for build artifacts and per-project
/// caches (`node_modules`, `.next`, `target/`, `Pods/`, …).
///
/// Performance:
///   * Depth-limited `FileManager.enumerator` — Swift-native, no shell escaping.
///   * **Prunes** the moment we hit a match: we don't descend into
///     `node_modules`, so a tree with 50k JS files inside doesn't get walked.
///   * Found paths are persisted in `project-paths.json` so the menu repopulates
///     instantly on next launch without re-walking the disk.
///
/// Sizes are NOT computed here. We hand the entries to `InspectorRegistry.all`,
/// the existing `CachedInspectorScanner` measures + caches them with the same
/// mtime-aware machinery used for everything else.
enum ProjectScanner {

    // MARK: - patterns

    /// (folder name, human label). Order doesn't matter; first match wins.
    private static let patterns: [(name: String, label: String)] = [
        ("node_modules",   "node_modules"),
        (".next",          ".next"),
        (".nuxt",          ".nuxt"),
        (".parcel-cache",  ".parcel-cache"),
        (".turbo",         ".turbo"),
        (".svelte-kit",    ".svelte-kit"),
        ("dist",           "dist"),
        ("build",          "build"),
        ("out",            "out"),
        ("target",         "target"),
        (".gradle",        ".gradle (project)"),
        ("vendor",         "vendor"),
        ("Pods",           "Pods (project)"),
        ("DerivedData",    "DerivedData (project)"),
        ("__pycache__",    "__pycache__"),
        (".pytest_cache",  ".pytest_cache"),
        (".tox",           ".tox"),
        (".venv",          ".venv"),
        ("venv",           "venv"),
        (".terraform",     ".terraform"),
        (".cache",         "project .cache")
    ]
    private static let patternSet: Set<String> = Set(patterns.map { $0.name })
    private static let patternLabels: [String: String] = Dictionary(uniqueKeysWithValues: patterns.map { ($0.name, $0.label) })

    // MARK: - staleness classification

    /// How likely is this artifact to be safely deletable?
    enum Status {
        case active     // touched in the last 30 days — keep, don't bulk-reclaim
        case idle       // 30–90 days since activity
        case stale      // 90+ days since activity in both artifact and manifest
        case orphan     // no manifest in parent — project probably gone
    }

    /// Files that signal "this is an actual project root". When the
    /// artifact's parent has one of these we treat the manifest's mtime as
    /// the project's last-activity signal; when there's none we mark the
    /// artifact orphan.
    private static let manifestsByArtifact: [String: [String]] = [
        "node_modules":      ["package.json"],
        ".next":             ["package.json", "next.config.js", "next.config.ts", "next.config.mjs"],
        ".nuxt":             ["package.json", "nuxt.config.js", "nuxt.config.ts"],
        ".turbo":            ["package.json", "turbo.json"],
        ".svelte-kit":       ["package.json", "svelte.config.js"],
        ".parcel-cache":     ["package.json"],
        "dist":              ["package.json"],
        "build":             ["package.json", "build.gradle", "build.gradle.kts", "CMakeLists.txt", "pyproject.toml"],
        "out":               ["package.json"],
        "target":            ["Cargo.toml", "pom.xml", "build.sbt"],
        ".gradle":           ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"],
        "vendor":            ["composer.json", "go.mod", "Gemfile"],
        "Pods":              ["Podfile", "Podfile.lock"],
        "DerivedData":       ["Package.swift", "Project.pbxproj"],
        "__pycache__":       ["pyproject.toml", "setup.py", "setup.cfg", "requirements.txt", "Pipfile"],
        ".pytest_cache":     ["pyproject.toml", "setup.py", "pytest.ini", "tox.ini"],
        ".tox":              ["tox.ini", "pyproject.toml"],
        ".venv":             ["pyproject.toml", "setup.py", "requirements.txt", "Pipfile"],
        "venv":              ["pyproject.toml", "setup.py", "requirements.txt", "Pipfile"],
        ".terraform":        ["main.tf", "terraform.tf"],
        ".cache":            ["package.json", "pyproject.toml", "Cargo.toml"]
    ]

    private static func classify(artifact: URL) -> (status: Status, daysIdle: Int, manifestName: String?) {
        let parent = artifact.deletingLastPathComponent()
        let name = artifact.lastPathComponent
        let manifestCandidates = manifestsByArtifact[name] ?? []
        var foundManifest: URL?
        for candidate in manifestCandidates {
            let p = parent.appendingPathComponent(candidate)
            if FS.exists(p) { foundManifest = p; break }
        }

        let artifactMtime = FS.mostRecentChildMTime(artifact) ?? FS.lastModified(artifact)
        let manifestMtime = foundManifest.flatMap { FS.lastModified($0) }

        // Orphan: we expected a manifest and there isn't one.
        if !manifestCandidates.isEmpty && foundManifest == nil {
            let days = artifactMtime.map { daysSince($0) } ?? 9999
            return (.orphan, days, nil)
        }

        // Idle measure = recency of EITHER artifact or manifest. If the
        // user opened the project last week, manifest mtime is recent and
        // we leave their node_modules alone.
        let candidates: [Date] = [artifactMtime, manifestMtime].compactMap { $0 }
        let referenceDate = candidates.max() ?? Date.distantPast
        let daysIdle = daysSince(referenceDate)
        let manifestName = foundManifest?.lastPathComponent

        if daysIdle >= 90 { return (.stale, daysIdle, manifestName) }
        if daysIdle >= 30 { return (.idle,  daysIdle, manifestName) }
        return (.active, daysIdle, manifestName)
    }

    private static func daysSince(_ d: Date) -> Int {
        return max(0, Int(Date().timeIntervalSince(d) / 86_400))
    }

    // MARK: - presentation helpers

    private static func decoratedLabel(parentName: String,
                                       artifactName: String,
                                       status: Status,
                                       daysIdle: Int) -> String {
        let base = "\(parentName)/\(artifactName)"
        switch status {
        case .active: return base
        case .idle:   return "\(base) · idle \(daysIdle)d"
        case .stale:  return "\(base) · stale \(daysIdle)d"
        case .orphan: return "\(base) · orphan"
        }
    }

    private static func explainStatus(status: Status,
                                      daysIdle: Int,
                                      manifestName: String?,
                                      parent: String) -> String {
        switch status {
        case .active:
            return "active project — last touched \(daysIdle) day\(daysIdle == 1 ? "" : "s") ago (\(parent))"
        case .idle:
            let manifest = manifestName.map { " (\($0))" } ?? ""
            return "idle \(daysIdle)d — included in bulk reclaim. Project\(manifest) at: \(parent)"
        case .stale:
            let manifest = manifestName.map { " (\($0))" } ?? ""
            return "stale \(daysIdle)d — both folder and manifest\(manifest) untouched. Safe to delete."
        case .orphan:
            return "orphan — no manifest found in parent. Project probably gone. Safe to delete."
        }
    }

    /// Default roots scanned when the user hasn't customised them. Common
    /// dev workspace folders on a Mac.
    static var defaultRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("code"),
            home.appendingPathComponent("Code"),
            home.appendingPathComponent("Projects"),
            home.appendingPathComponent("projects"),
            home.appendingPathComponent("Developer"),
            home.appendingPathComponent("Documents"),
            home.appendingPathComponent("Sites"),
            home.appendingPathComponent("workspace"),
            home.appendingPathComponent("dev"),
            home.appendingPathComponent("Documents/Gridam")
        ]
    }

    // MARK: - scanning

    /// Walks `roots` to `maxDepth` (default 5), prunes match directories,
    /// returns one `InspectEntry` per match. **Does not** measure sizes —
    /// downstream `CachedInspectorScanner` handles that with its mtime
    /// cache and parallel `du -sk`.
    static func scan(roots: [URL] = defaultRoots, maxDepth: Int = 5) -> [InspectEntry] {
        var entries: [InspectEntry] = []
        for root in roots where FS.exists(root) {
            entries.append(contentsOf: scanRoot(root, maxDepth: maxDepth))
        }
        // Persist to disk before returning so subsequent launches see them.
        ProjectScanCache.save(entries)
        return entries
    }

    /// Loads the last persisted scan result, filtered to entries whose
    /// paths still exist. Cheap (one JSON read, no FS walk).
    static func cachedEntries() -> [InspectEntry] {
        return ProjectScanCache.load().filter { FS.exists($0.path) }
    }

    /// Removes the persisted cache. Used by the "Clear projects" action.
    static func clearCache() {
        ProjectScanCache.clear()
    }

    // MARK: - core walker

    private static func scanRoot(_ root: URL, maxDepth: Int) -> [InspectEntry] {
        var out: [InspectEntry] = []
        let keys: [URLResourceKey] = [.isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .producesRelativePathURLs],
            errorHandler: { _, _ in true }
        ) else {
            return []
        }

        let rootDepth = root.pathComponents.count

        for case let url as URL in enumerator {
            // Depth check — prune anything deeper than maxDepth.
            let absURL = url.absoluteURL
            let depth = absURL.pathComponents.count - rootDepth
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }

            // Only directories interest us.
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { continue }

            let name = url.lastPathComponent
            guard patternSet.contains(name) else { continue }

            // Match: emit and prune. We never descend into node_modules etc.
            enumerator.skipDescendants()

            let target = absURL.standardized
            let parentName = target.deletingLastPathComponent().lastPathComponent
            let info = classify(artifact: target)

            // Badge format: "my-project/node_modules · stale 95d"
            //               "old-app/node_modules · orphan"
            //               "active-app/node_modules"          (no decoration)
            let label = decoratedLabel(parentName: parentName,
                                       artifactName: name,
                                       status: info.status,
                                       daysIdle: info.daysIdle)
            let note = explainStatus(status: info.status,
                                     daysIdle: info.daysIdle,
                                     manifestName: info.manifestName,
                                     parent: target.deletingLastPathComponent().path)

            // Active artifacts: still findable, still trashable manually,
            // but they don't get the official cleanup command — so the
            // bulk reclaim button leaves them alone.
            let cleanup: String? = info.status == .active
                ? nil
                : "rm -rf \"\(target.path.replacingOccurrences(of: "\"", with: "\\\""))\""

            let entry = InspectEntry(
                label: label,
                path: target,
                category: .projectArtifacts,
                note: note,
                cleanup: cleanup,
                dangerToTrash: false
            )
            out.append(entry)
        }
        return out
    }
}

// MARK: - Cache (persists the list of artifact paths, not their sizes)

private enum ProjectScanCache {
    static var url: URL {
        IndexStore.defaultDirectory.appendingPathComponent("project-paths.json")
    }

    /// Row format on disk — minimal so the file stays small even with many
    /// entries.
    private struct Row: Codable {
        let label: String
        let path: String
        let note: String?
        let cleanup: String?
    }

    static func load() -> [InspectEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        guard let rows = try? JSONDecoder().decode([Row].self, from: data) else { return [] }
        return rows.map { row in
            InspectEntry(
                label: row.label,
                path: URL(fileURLWithPath: row.path),
                category: .projectArtifacts,
                note: row.note,
                cleanup: row.cleanup,
                dangerToTrash: false
            )
        }
    }

    static func save(_ entries: [InspectEntry]) {
        let rows = entries.map {
            Row(label: $0.label, path: $0.path.path, note: $0.note, cleanup: $0.cleanup)
        }
        if let data = try? JSONEncoder().encode(rows) {
            try? FileManager.default.createDirectory(at: IndexStore.defaultDirectory, withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }

    static func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
