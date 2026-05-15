import Foundation

/// How risky it is to delete an entry. Ordered from safest to most painful.
/// The menu sorts findings by this first, so the user reads top-down from
/// "definitely safe" to "be careful". Auto-derived from `cleanup` +
/// `dangerToTrash` + `category` in `InspectEntry.safetyClass`, with an
/// explicit override available for the few edge cases.
enum SafetyClass: Int, Comparable, CaseIterable {
    /// 🟢 Pure cache — tools rebuild it automatically on next use.
    case cache = 0
    /// 🟡 Rebuildable data — works, but costs you a `docker pull`,
    /// re-downloaded models, re-installed packages, etc.
    case data = 1
    /// 🔴 Installation — losing it means a manual reinstall + reconfig.
    case installation = 2
    /// ⚫ User data — sessions, history, backups. Irrecoverable.
    case userData = 3

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .cache:        return "cache"
        case .data:         return "data"
        case .installation: return "install"
        case .userData:     return "user data"
        }
    }
}

/// Categories used to group inspect findings in the report.
enum InspectCategory: String, CaseIterable {
    case projectArtifacts = "Project artifacts"
    case appleDev         = "Apple Dev (Xcode · iOS)"
    case android          = "Android"
    case ai               = "AI / LLMs"
    case containers       = "Containers & VMs"
    case node             = "Node.js"
    case python           = "Python"
    case languages        = "Other languages"
    case flutter          = "Flutter / Dart"
    case homebrew         = "Homebrew"
    case iosBackups       = "iOS Backups"
    case editors          = "Editors / IDEs"
    case apps             = "Apps"
    case browsers         = "Browsers"
    case userFolders      = "User folders"
}

/// One known location to inspect for space usage.
struct InspectEntry {
    let label: String
    let path: URL
    let category: InspectCategory
    /// Human hint shown in the menu / verbose CLI output.
    let note: String?
    /// Shell line to free space for this entry (run via `/bin/sh -c`).
    /// `nil` means there is no official command — UI offers Trash only.
    let cleanup: String?
    /// If true, the UI hides the "Move to Trash" action — typically because
    /// the path holds irrecoverable user data (e.g. iOS device backups,
    /// browser profiles, Trash itself).
    let dangerToTrash: Bool
    /// Explicit safety class. `nil` falls back to the auto-classifier in
    /// `safetyClass`. Use only when the heuristic is wrong.
    let safetyOverride: SafetyClass?

    init(label: String,
         path: URL,
         category: InspectCategory,
         note: String? = nil,
         cleanup: String? = nil,
         dangerToTrash: Bool = false,
         safetyOverride: SafetyClass? = nil) {
        self.label = label
        self.path = path
        self.category = category
        self.note = note
        self.cleanup = cleanup
        self.dangerToTrash = dangerToTrash
        self.safetyOverride = safetyOverride
    }

    /// Auto-classifies the safety of deleting this entry.
    ///
    /// The heuristic answers four questions in order:
    ///   1. Is it explicitly overridden? Use that.
    ///   2. Is trashing it blocked? Then it's either user data (browsers /
    ///      backups / user folders) or an installation (everything else).
    ///   3. Does it lack an automated cleanup? It's rebuildable data
    ///      (models, container state).
    ///   4. Otherwise it's a pure cache.
    var safetyClass: SafetyClass {
        if let explicit = safetyOverride { return explicit }
        if dangerToTrash {
            if cleanup != nil { return .data }   // e.g. Docker daemon up
            switch category {
            case .browsers, .iosBackups, .userFolders, .apps, .editors:
                return .userData
            default:
                return .installation
            }
        }
        if cleanup == nil { return .data }
        return .cache
    }
}

extension Array where Element == InspectFinding {
    /// Sort safest-first, then biggest-first within each safety bucket.
    /// This is the canonical order shown to the user — the menu reads
    /// top-down from "definitely safe to delete" to "be careful".
    func sortedBySafetyThenSize() -> [InspectFinding] {
        return self.sorted { a, b in
            let sa = a.entry.safetyClass, sb = b.entry.safetyClass
            if sa != sb { return sa < sb }
            return a.sizeBytes > b.sizeBytes
        }
    }
}

/// A scanned entry with its measured size.
struct InspectFinding {
    let entry: InspectEntry
    let sizeBytes: UInt64
    /// Size from the previous scan, if any. Used by the UI to render deltas.
    let previousSizeBytes: UInt64?

    /// Signed change since the previous scan. `nil` if there's no prior
    /// measurement (e.g. first scan). Positive = grew, negative = shrunk.
    var delta: Int64? {
        guard let prev = previousSizeBytes else { return nil }
        return Int64(sizeBytes) - Int64(prev)
    }

    init(entry: InspectEntry, sizeBytes: UInt64, previousSizeBytes: UInt64? = nil) {
        self.entry = entry
        self.sizeBytes = sizeBytes
        self.previousSizeBytes = previousSizeBytes
    }
}

/// Curated list of paths known to grow into big space consumers on a Mac
/// developer machine. Adding a new entry is one line.
enum InspectorRegistry {
    /// Curated registry plus user paths plus dynamic project artifacts.
    /// Resolution order on duplicate `path`: curated > custom > project.
    static var all: [InspectEntry] {
        let curated = entries
        let custom = CustomPaths.load()
        let projects = ProjectScanner.cachedEntries()

        var seen = Set(curated.map { $0.path.path })
        var out = curated
        for e in custom where !seen.contains(e.path.path) {
            out.append(e); seen.insert(e.path.path)
        }
        for e in projects where !seen.contains(e.path.path) {
            out.append(e); seen.insert(e.path.path)
        }
        return out
    }

    /// Curated entries, re-evaluated on every access so runtime conditions
    /// (Docker daemon up/down, missing CLI tools, …) flip cleanup
    /// availability without an app restart.
    static var entries: [InspectEntry] {
        var list = staticEntries
        list.append(computeDockerEntry())
        return list.map { gateByToolAvailability($0) }
    }

    /// If the entry's cleanup command needs an external tool that isn't on
    /// the user's PATH, swap the cleanup for `nil` and explain why in the
    /// note. This way the bulk reclaim never tries to run something that
    /// will obviously fail, and the submenu makes the gap obvious to the
    /// user.
    private static func gateByToolAvailability(_ entry: InspectEntry) -> InspectEntry {
        guard let cleanup = entry.cleanup,
              let tool = primaryTool(of: cleanup),
              !UserPath.contains(tool: tool)
        else { return entry }

        return InspectEntry(
            label: entry.label,
            path: entry.path,
            category: entry.category,
            note: "`\(tool)` not installed — install it to enable reclaim. The folder is still trashable manually.",
            cleanup: nil,
            dangerToTrash: entry.dangerToTrash
        )
    }

    /// Pulls the executable name out of a shell line. Returns `nil` when
    /// the line uses only ubiquitous builtins (`rm`, `mv`) or wraps the
    /// real work in a shell guard like `( command -v … ) ; rm …`.
    private static func primaryTool(of shellLine: String) -> String? {
        let trimmed = shellLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.split(separator: " ").first else { return nil }
        let head = String(first)
        if head.hasPrefix("(") { return nil }           // guarded compound — always-runnable
        if head == "rm" || head == "mv" { return nil }  // builtins
        return head
    }


    /// Docker entry whose actions depend on whether the daemon is up.
    ///
    /// - Daemon **running**: offer `docker system prune` (clean, preserves
    ///   the VM itself). Trash is hidden because mutating the VM disk
    ///   while Docker is writing to it can corrupt the image.
    /// - Daemon **stopped**: trash IS safe — nothing is holding file
    ///   handles. We hide the prune command (no daemon to talk to) and
    ///   expose Trash so the user can reclaim ~13 GB at the cost of
    ///   needing to rebuild containers / re-pull images afterwards.
    private static func computeDockerEntry() -> InspectEntry {
        let path = p("Library/Containers/com.docker.docker")
        if RuntimeProbe.isDockerDaemonRunning() {
            return InspectEntry(
                label: "Docker Desktop",
                path: path,
                category: .containers,
                note: "drops ALL containers, images, networks, volumes",
                cleanup: "docker system prune -af --volumes",
                dangerToTrash: true   // daemon is writing — trashing would corrupt
            )
        }
        return InspectEntry(
            label: "Docker Desktop",
            path: path,
            category: .containers,
            note: "Docker Desktop is stopped. Move to Trash reclaims ~all of this entry; you'll need to rebuild containers and re-pull images after restarting Docker.",
            cleanup: nil,
            dangerToTrash: false   // daemon stopped — trash is safe
        )
    }

    private static let home = FileManager.default.homeDirectoryForCurrentUser
    private static func p(_ tail: String) -> URL { home.appendingPathComponent(tail) }
    private static func abs(_ path: String) -> URL { URL(fileURLWithPath: path) }

    private static let staticEntries: [InspectEntry] = [
        // Apple Dev — Xcode, iOS Simulator, CocoaPods, SPM, Carthage ─────
        InspectEntry(label: "Xcode DerivedData",
                     path: p("Library/Developer/Xcode/DerivedData"),
                     category: .appleDev,
                     note: "build artifacts + indexes for every Xcode project — rebuilt by next build",
                     cleanup: "rm -rf \"$HOME/Library/Developer/Xcode/DerivedData\"/* 2>/dev/null || true"),

        InspectEntry(label: "Xcode Module Cache",
                     path: p("Library/Developer/Xcode/DerivedData/ModuleCache.noindex"),
                     category: .appleDev,
                     note: "subset of DerivedData (precompiled modules) — rebuilt by next build"),

        InspectEntry(label: "CocoaPods cache",
                     path: p("Library/Caches/CocoaPods"),
                     category: .appleDev,
                     note: "cached pod sources — rebuilt by next `pod install`",
                     cleanup: "rm -rf \"$HOME/Library/Caches/CocoaPods\"/* 2>/dev/null || true"),

        InspectEntry(label: "Swift Package Manager cache",
                     path: p("Library/Caches/org.swift.swiftpm"),
                     category: .appleDev,
                     note: "SPM dependency clone cache — rebuilt by next resolve",
                     cleanup: "rm -rf \"$HOME/Library/Caches/org.swift.swiftpm\"/repositories 2>/dev/null || true"),

        InspectEntry(label: "Carthage cache",
                     path: p("Library/Caches/org.carthage.CarthageKit"),
                     category: .appleDev,
                     note: "Carthage dependency cache — rebuilt by next bootstrap",
                     cleanup: "rm -rf \"$HOME/Library/Caches/org.carthage.CarthageKit\"/* 2>/dev/null || true"),

        InspectEntry(label: "iOS DeviceSupport",
                     path: p("Library/Developer/Xcode/iOS DeviceSupport"),
                     category: .appleDev,
                     note: "downloaded device symbols — re-fetched when you connect a device",
                     cleanup: "rm -rf \"$HOME/Library/Developer/Xcode/iOS DeviceSupport\"/* 2>/dev/null || true"),

        InspectEntry(label: "watchOS DeviceSupport",
                     path: p("Library/Developer/Xcode/watchOS DeviceSupport"),
                     category: .appleDev,
                     note: "downloaded watch symbols — re-fetched when you connect a device",
                     cleanup: "rm -rf \"$HOME/Library/Developer/Xcode/watchOS DeviceSupport\"/* 2>/dev/null || true"),

        InspectEntry(label: "tvOS DeviceSupport",
                     path: p("Library/Developer/Xcode/tvOS DeviceSupport"),
                     category: .appleDev,
                     note: "downloaded tvOS symbols — re-fetched on next connect",
                     cleanup: "rm -rf \"$HOME/Library/Developer/Xcode/tvOS DeviceSupport\"/* 2>/dev/null || true"),

        // Two complementary entries: one safe (only deletes simulators whose
        // runtime is gone — usually a fraction of the total), one aggressive
        // (wipes all simulator data, keeping definitions). The path is the
        // same in both because that's what's being measured; the labels and
        // notes make the actual freed amount honest.
        InspectEntry(label: "iOS Simulators — outdated runtimes only",
                     path: p("Library/Developer/CoreSimulator/Devices"),
                     category: .appleDev,
                     note: "Deletes simulators whose iOS/tvOS/watchOS runtime is gone. Frees 0 GB if all current runtimes are installed.",
                     cleanup: "xcrun simctl delete unavailable",
                     safetyOverride: .data),

        InspectEntry(label: "iOS Simulators — erase all data",
                     path: p("Library/Developer/CoreSimulator/Devices"),
                     category: .appleDev,
                     note: "Shuts down and erases data of every simulator. Definitions are kept; first launch starts clean. Frees the bulk of the listed size.",
                     cleanup: "xcrun simctl shutdown all 2>/dev/null; xcrun simctl erase all",
                     safetyOverride: .installation),

        InspectEntry(label: "CoreSimulator Caches",
                     path: p("Library/Developer/CoreSimulator/Caches"),
                     category: .appleDev,
                     note: "iOS simulator runtime cache — rebuilt on next sim boot",
                     cleanup: "rm -rf \"$HOME/Library/Developer/CoreSimulator/Caches\"/* 2>/dev/null || true"),

        InspectEntry(label: "Xcode Archives",
                     path: p("Library/Developer/Xcode/Archives"),
                     category: .appleDev,
                     note: "signed app archives — may contain App-Store-uploaded builds. Review in Xcode → Organizer before deleting.",
                     dangerToTrash: true),

        // Android ─────────────────────────────────────────────────────────
        InspectEntry(label: "Android SDK",        path: p("Library/Android/sdk"),          category: .android,
                     note: "installation — managed by Android Studio SDK Manager",
                     dangerToTrash: true),
        InspectEntry(label: "AVDs (emulators)",   path: p(".android/avd"),                  category: .android,
                     note: "virtual device state — delete individual AVDs from Android Studio",
                     dangerToTrash: true,
                     safetyOverride: .data),    // AVDs are rebuildable, not installs
        InspectEntry(label: "Gradle caches",      path: p(".gradle"),                       category: .android,
                     note: "official: stop daemons + drop ~/.gradle/caches",
                     cleanup: "( command -v gradle >/dev/null && gradle --stop ) ; rm -rf \"$HOME/.gradle/caches\""),
        InspectEntry(label: "Konan (Kotlin/Native)", path: p(".konan"),                     category: .android,
                     note: "downloaded Kotlin/Native compilers — re-fetched on next build",
                     dangerToTrash: true,
                     safetyOverride: .data),    // compilers re-downloaded automatically

        // AI / LLMs ───────────────────────────────────────────────────────
        InspectEntry(label: "Ollama models",      path: p(".ollama/models"),                category: .ai, note: "delete specific models with `ollama rm <model>`"),
        InspectEntry(label: "HuggingFace cache",  path: p(".cache/huggingface"),            category: .ai, note: nil),
        InspectEntry(label: "LM Studio models",   path: p(".cache/lm-studio"),              category: .ai, note: nil),
        InspectEntry(label: "LM Studio app",      path: p("Library/Application Support/LM Studio"), category: .ai,
                     note: "app data + downloaded models — manage from LM Studio",
                     dangerToTrash: true),
        InspectEntry(label: "Whisper models",     path: p(".cache/whisper"),                category: .ai, note: nil),

        // Containers / VMs ────────────────────────────────────────────────
        // Docker Desktop entry is computed dynamically by
        // `computeDockerEntry()` — its cleanup command depends on whether
        // the daemon is currently reachable.
        InspectEntry(label: "Docker group",       path: p("Library/Group Containers/group.com.docker"), category: .containers,
                     note: "Docker shared app data — stop Docker before trashing"),
        InspectEntry(label: "OrbStack",           path: p(".orbstack"),                     category: .containers,
                     note: "OrbStack VM disks + containers — stop OrbStack before trashing"),
        InspectEntry(label: "Colima",             path: p(".colima"),                       category: .containers,
                     note: "Colima VM disks — `colima stop` before trashing"),
        InspectEntry(label: "Lima",               path: p(".lima"),                         category: .containers,
                     note: "Lima VM disks — `limactl stop <name>` before trashing"),
        InspectEntry(label: "Podman storage",     path: p(".local/share/containers"),       category: .containers,
                     note: "Podman containers + images — `podman machine stop` before trashing"),
        InspectEntry(label: "Multipass",          path: p("Library/Application Support/multipassd"), category: .containers,
                     note: "Multipass VM instances — stop multipassd before trashing"),

        // Node.js ─────────────────────────────────────────────────────────
        InspectEntry(label: "npm cache",          path: p(".npm"),                          category: .node,
                     note: "rebuilt automatically on next `npm install`",
                     cleanup: "npm cache clean --force"),
        InspectEntry(label: "pnpm store",         path: p(".pnpm-store"),                   category: .node,
                     note: "removes packages not referenced by any lockfile",
                     cleanup: "pnpm store prune"),
        InspectEntry(label: "pnpm (local)",       path: p("Library/pnpm"),                  category: .node,
                     note: "pnpm itself + node versions managed by pnpm",
                     dangerToTrash: true),
        InspectEntry(label: "Yarn cache",         path: p(".yarn/cache"),                   category: .node,
                     note: "rebuilt by next `yarn install`",
                     cleanup: "yarn cache clean"),
        InspectEntry(label: "Yarn berry",         path: p(".yarn/berry"),                   category: .node,
                     note: "Yarn 2+ distribution itself", dangerToTrash: true),
        InspectEntry(label: "nvm versions",       path: p(".nvm"),                          category: .node,
                     note: "installed Node versions — use `nvm uninstall <ver>`",
                     dangerToTrash: true),
        InspectEntry(label: "fnm versions",       path: p("Library/Application Support/fnm_multishells"), category: .node,
                     note: "installed Node versions managed by fnm",
                     dangerToTrash: true),
        InspectEntry(label: "Volta",              path: p(".volta"),                        category: .node,
                     note: "Volta runtime + installed tools",
                     dangerToTrash: true),
        InspectEntry(label: "Bun cache",          path: p(".bun/install/cache"),            category: .node,
                     note: "rebuilt by next `bun install`",
                     cleanup: "bun pm cache rm"),

        // Python ──────────────────────────────────────────────────────────
        InspectEntry(label: "pip cache (Library)", path: p("Library/Caches/pip"),           category: .python,
                     cleanup: "pip cache purge"),
        InspectEntry(label: "pip cache (~/.cache)", path: p(".cache/pip"),                  category: .python,
                     cleanup: "pip cache purge"),
        InspectEntry(label: "uv cache",           path: p(".cache/uv"),                     category: .python,
                     note: "direct rm of archives/wheels/git/simple subdirs — `uv cache clean` hangs when uv tool processes (MCP servers, etc.) hold the cache lock. Disk may take seconds to fully release if those tools have files open.",
                     cleanup: "find \"$HOME/.cache/uv\" -mindepth 1 -maxdepth 1 -type d \\( -name 'archive-v*' -o -name 'wheels-v*' -o -name 'built-wheels-v*' -o -name 'sdists-v*' -o -name 'git-v*' -o -name 'simple-v*' \\) -exec rm -rf {} + || true"),
        InspectEntry(label: "Poetry cache",       path: p("Library/Caches/pypoetry"),       category: .python, note: nil),
        InspectEntry(label: "pyenv versions",     path: p(".pyenv/versions"),               category: .python,
                     note: "installed Pythons — use `pyenv uninstall <ver>`",
                     dangerToTrash: true),
        InspectEntry(label: "conda envs",         path: p("anaconda3"),                     category: .python,
                     note: "Anaconda installation + envs", dangerToTrash: true),
        InspectEntry(label: "miniconda",          path: p("miniconda3"),                    category: .python,
                     note: "Miniconda installation + envs", dangerToTrash: true),
        InspectEntry(label: "mamba root",         path: p("mambaforge"),                    category: .python,
                     note: "Mamba installation + envs", dangerToTrash: true),

        // Other languages ────────────────────────────────────────────────
        InspectEntry(label: "Rust cargo cache",   path: p(".cargo"),                        category: .languages, note: "install cargo-cache first: `cargo install cargo-cache`"),
        InspectEntry(label: "Rust toolchains",    path: p(".rustup/toolchains"),            category: .languages,
                     note: "installed Rust toolchains — use `rustup toolchain uninstall <ver>`",
                     dangerToTrash: true),
        InspectEntry(label: "Go modules",         path: p("go/pkg/mod"),                    category: .languages,
                     cleanup: "go clean -modcache"),
        InspectEntry(label: "Go build cache",     path: p("Library/Caches/go-build"),       category: .languages,
                     cleanup: "go clean -cache"),
        InspectEntry(label: "rbenv versions",     path: p(".rbenv/versions"),               category: .languages,
                     note: "installed Rubies — use `rbenv uninstall <ver>`",
                     dangerToTrash: true),
        InspectEntry(label: "rvm rubies",         path: p(".rvm/rubies"),                   category: .languages,
                     note: "installed Rubies — use `rvm remove <ver>`",
                     dangerToTrash: true),
        InspectEntry(label: "Ruby gems",          path: p(".gem"),                          category: .languages, note: nil),
        InspectEntry(label: "Maven (~/.m2)",      path: p(".m2"),                           category: .languages, note: nil),
        InspectEntry(label: "Ivy cache",          path: p(".ivy2"),                         category: .languages, note: nil),
        InspectEntry(label: "Coursier cache",     path: p("Library/Caches/Coursier"),       category: .languages, note: nil),

        // Flutter / Dart ─────────────────────────────────────────────────
        InspectEntry(label: "Flutter SDK",        path: p("development/flutter"),           category: .flutter,
                     note: "installation — deleting breaks `flutter` until you reinstall (~3 GB download)",
                     dangerToTrash: true),
        InspectEntry(label: "Dart pub cache",     path: p(".pub-cache"),                    category: .flutter,
                     note: "rebuilt by `flutter pub get`",
                     cleanup: "rm -rf \"$HOME/.pub-cache/hosted\" && rm -rf \"$HOME/.pub-cache/git\""),
        InspectEntry(label: "fvm versions",       path: p("fvm"),                           category: .flutter,
                     note: "installed Flutter versions managed by fvm",
                     dangerToTrash: true),
        InspectEntry(label: "fvm (~/.fvm)",       path: p(".fvm"),                          category: .flutter,
                     note: "fvm install root", dangerToTrash: true),

        // Homebrew ───────────────────────────────────────────────────────
        InspectEntry(label: "Homebrew Cellar",    path: abs("/opt/homebrew/Cellar"),        category: .homebrew,
                     note: "installed formulae — uninstall with `brew uninstall <pkg>`",
                     dangerToTrash: true),
        InspectEntry(label: "Homebrew Caskroom",  path: abs("/opt/homebrew/Caskroom"),      category: .homebrew,
                     note: "installed casks (apps) — uninstall with `brew uninstall --cask <name>`",
                     dangerToTrash: true),
        InspectEntry(label: "Homebrew cache",     path: p("Library/Caches/Homebrew"),       category: .homebrew,
                     note: "prunes downloads, builds, and old versions",
                     cleanup: "brew cleanup -s --prune=all"),

        // iOS Backups ────────────────────────────────────────────────────
        InspectEntry(label: "iOS device backups", path: p("Library/Application Support/MobileSync/Backup"), category: .iosBackups,
                     note: "Finder/iTunes phone backups — irrecoverable if deleted",
                     dangerToTrash: true),

        // Editors / IDEs ─────────────────────────────────────────────────
        InspectEntry(label: "JetBrains caches",   path: p("Library/Caches/JetBrains"),      category: .editors, note: nil),
        InspectEntry(label: "JetBrains app data", path: p("Library/Application Support/JetBrains"), category: .editors,
                     note: "IDE settings, plugins, indexes — deleting resets your IDEs",
                     dangerToTrash: true),
        InspectEntry(label: "Android Studio cache", path: p("Library/Caches/Google/AndroidStudio"), category: .editors, note: nil),
        InspectEntry(label: "VS Code app data",   path: p("Library/Application Support/Code"), category: .editors,
                     note: "extensions, settings, workspace storage — deleting resets VS Code",
                     dangerToTrash: true),
        InspectEntry(label: "VS Code cache",      path: p("Library/Caches/com.microsoft.VSCode"), category: .editors, note: nil),
        InspectEntry(label: "Cursor",             path: p("Library/Application Support/Cursor"), category: .editors,
                     note: "Cursor settings + chat history", dangerToTrash: true),
        InspectEntry(label: "Zed",                path: p("Library/Application Support/Zed"), category: .editors,
                     note: "Zed settings + project state", dangerToTrash: true),

        // Apps ───────────────────────────────────────────────────────────
        InspectEntry(label: "Slack",              path: p("Library/Application Support/Slack"), category: .apps,
                     note: "logged-in sessions + cached messages",
                     dangerToTrash: true),
        InspectEntry(label: "Discord",            path: p("Library/Application Support/discord"), category: .apps,
                     note: "logged-in session + cache",
                     dangerToTrash: true),
        InspectEntry(label: "Microsoft Teams",    path: p("Library/Application Support/Microsoft/Teams"), category: .apps,
                     note: "logged-in session + cache",
                     dangerToTrash: true),
        InspectEntry(label: "Zoom",               path: p("Library/Application Support/zoom.us"), category: .apps,
                     note: "settings + local recordings (check before deleting)",
                     dangerToTrash: true),
        InspectEntry(label: "WhatsApp",           path: p("Library/Group Containers/group.net.whatsapp.WhatsApp.shared"), category: .apps,
                     note: "message history",
                     dangerToTrash: true),
        InspectEntry(label: "Spotify cache",      path: p("Library/Application Support/Spotify/PersistentCache"), category: .apps, note: "rebuilt automatically"),
        InspectEntry(label: "Notion",             path: p("Library/Application Support/Notion"), category: .apps,
                     note: "logged-in session", dangerToTrash: true),
        InspectEntry(label: "Obsidian",           path: p("Library/Application Support/obsidian"), category: .apps,
                     note: "Obsidian settings + vault index", dangerToTrash: true),
        InspectEntry(label: "Figma",              path: p("Library/Application Support/Figma"), category: .apps,
                     note: "logged-in session + offline files", dangerToTrash: true),

        // Browsers ───────────────────────────────────────────────────────
        InspectEntry(label: "Chrome app data",    path: p("Library/Application Support/Google/Chrome"), category: .browsers,
                     note: "profiles + history + passwords — clear from Chrome instead",
                     dangerToTrash: true),
        InspectEntry(label: "Chrome cache",       path: p("Library/Caches/Google/Chrome"),  category: .browsers, note: nil),
        InspectEntry(label: "Safari cache",       path: p("Library/Caches/com.apple.Safari"), category: .browsers, note: nil),
        InspectEntry(label: "Brave",              path: p("Library/Application Support/BraveSoftware"), category: .browsers,
                     note: "profiles + history",
                     dangerToTrash: true),
        InspectEntry(label: "Firefox",            path: p("Library/Application Support/Firefox"), category: .browsers,
                     note: "profiles + history",
                     dangerToTrash: true),
        InspectEntry(label: "Arc",                path: p("Library/Application Support/Arc"), category: .browsers,
                     note: "profiles + tabs",
                     dangerToTrash: true),

        // User folders ───────────────────────────────────────────────────
        InspectEntry(label: "Downloads",          path: p("Downloads"),                     category: .userFolders, note: nil,                                  dangerToTrash: true),
        InspectEntry(label: "Desktop",            path: p("Desktop"),                       category: .userFolders, note: nil,                                  dangerToTrash: true),
        InspectEntry(label: "Trash",              path: p(".Trash"),                        category: .userFolders, note: "empty with Finder → Empty Trash",     dangerToTrash: true),
        InspectEntry(label: "Movies",             path: p("Movies"),                        category: .userFolders, note: nil,                                  dangerToTrash: true)
    ]
}

/// Computes sizes for inspect entries. Parallelized — size measurement on
/// large trees like Docker or Ollama is I/O-bound and benefits from running
/// many paths concurrently.
struct InspectorScanner {
    func scan(minBytes: UInt64, only: Set<InspectCategory> = []) -> [InspectFinding] {
        let entries = only.isEmpty
            ? InspectorRegistry.entries
            : InspectorRegistry.entries.filter { only.contains($0.category) }

        // Two-step: parallel size, then filter+sort. Distinct write indices
        // make the buffer safe without locking.
        var rawSizes = [UInt64](repeating: 0, count: entries.count)
        rawSizes.withUnsafeMutableBufferPointer { buf in
            DispatchQueue.concurrentPerform(iterations: entries.count) { i in
                let path = entries[i].path
                guard FS.exists(path) else { return }
                buf[i] = SizeMeasurer.size(of: path)
            }
        }

        var out: [InspectFinding] = []
        out.reserveCapacity(entries.count)
        for (i, e) in entries.enumerated() {
            let size = rawSizes[i]
            guard size >= minBytes else { continue }
            out.append(InspectFinding(entry: e, sizeBytes: size))
        }
        return out.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    /// Generic top-N: scan immediate children of `root` and rank by size.
    /// Useful for exploring "where did the space go in this folder?".
    func topN(root: URL, count: Int) -> [(URL, UInt64)] {
        let children = FS.directChildren(root)
        var sizes = [UInt64](repeating: 0, count: children.count)
        sizes.withUnsafeMutableBufferPointer { buf in
            DispatchQueue.concurrentPerform(iterations: children.count) { i in
                buf[i] = SizeMeasurer.size(of: children[i])
            }
        }
        let pairs = zip(children, sizes).sorted { $0.1 > $1.1 }
        return Array(pairs.prefix(count))
    }
}
