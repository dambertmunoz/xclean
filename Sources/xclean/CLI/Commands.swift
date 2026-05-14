import Foundation
import ArgumentParser

@main
struct XClean: ParsableCommand {
    /// When launched from inside an `.app` bundle (Bundle.main has an
    /// identifier), default to `menu` mode. From a terminal, default to
    /// the dry-run `scan` view so users see what's there without doing
    /// anything.
    private static var defaultSub: ParsableCommand.Type {
        return Bundle.main.bundleIdentifier != nil ? Menu.self : Scan.self
    }

    static let configuration = CommandConfiguration(
        commandName: "xclean",
        abstract: "Smart disk-space reclaimer for Xcode, Simulators, CocoaPods, SPM and Carthage.",
        version: "0.3.0",
        subcommands: [Scan.self, Clean.self, Doctor.self, Stats.self, Inspect.self, Menu.self, Reclaim.self, License.self],
        defaultSubcommand: defaultSub
    )
}

// MARK: - scan

struct Scan: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scan",
        abstract: "Show what would be cleaned, without changing anything."
    )

    @OptionGroup var shared: SharedOptions

    mutating func run() throws {
        let config = try shared.makeConfig(mode: .scan)
        let engine = CleanEngine(config: config)
        _ = try engine.run()
    }
}

// MARK: - clean

struct Clean: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clean",
        abstract: "Actually remove items. Interactive by default; --yes to skip prompts."
    )

    @OptionGroup var shared: SharedOptions

    @Flag(name: .shortAndLong, help: "Do not prompt; remove all safe candidates.")
    var yes: Bool = false

    mutating func run() throws {
        try LicenseGate.requireActiveLicense()
        let mode: Mode = yes ? .yes : .interactive
        let config = try shared.makeConfig(mode: mode)
        let engine = CleanEngine(config: config)
        _ = try engine.run()
    }
}

// MARK: - doctor

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Inspect a single plugin in verbose mode (no changes)."
    )

    @Argument(help: "Plugin ID (e.g. derived-data, simulators, cocoapods).")
    var plugin: String

    mutating func run() throws {
        let id = plugin.lowercased()
        let plugins = BuiltInPlugins.all.filter { $0.id == id }
        guard let chosen = plugins.first else {
            let known = BuiltInPlugins.all.map { $0.id }.joined(separator: ", ")
            throw ValidationError("Unknown plugin: \(plugin). Known: \(known).")
        }
        let config = RunConfig(
            mode: .scan,
            profile: .balanced,
            onlyPlugins: [chosen.id],
            skipPlugins: [],
            purge: false,
            includeRisky: false,
            verbose: true
        )
        let engine = CleanEngine(plugins: [chosen], config: config)
        _ = try engine.run()
    }
}

// MARK: - stats

struct Stats: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stats",
        abstract: "Print total size of each known cache root, without classification."
    )

    mutating func run() throws {
        print(ANSI.bold(ANSI.cyan("▎ xclean stats")))
        let rows: [(String, URL)] = [
            ("DerivedData",            Paths.derivedData),
            ("Archives",               Paths.archives),
            ("iOS DeviceSupport",      Paths.iOSDeviceSupport),
            ("watchOS DeviceSupport",  Paths.watchOSDeviceSupport),
            ("tvOS DeviceSupport",     Paths.tvOSDeviceSupport),
            ("ModuleCache",            Paths.moduleCache),
            ("CoreSimulator/Devices",  Paths.coreSimulatorDevices),
            ("CoreSimulator/Caches",   Paths.coreSimulatorCaches),
            ("CocoaPods cache",        Paths.cocoaPodsCache),
            ("SPM cache",              Paths.spmCache),
            ("Carthage cache",         Paths.carthageCache)
        ]

        var total: UInt64 = 0
        for (label, url) in rows {
            let size = FS.exists(url) ? FS.sizeOf(url) : 0
            total += size
            let line = "  " + label.padding(toLength: 24, withPad: " ", startingAt: 0)
                + ANSI.bold(ByteSize.human(size).padding(toLength: 12, withPad: " ", startingAt: 0))
                + ANSI.dim(url.path)
            print(line)
        }
        print("")
        print(ANSI.bold("Total: ") + ANSI.green(ByteSize.human(total)))
    }
}

// MARK: - inspect

struct Inspect: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inspect",
        abstract: "Find big space consumers across known dev-tool paths and user folders. Read-only.",
        discussion: """
        Scans a curated registry of locations known to grow into space hogs:
        Android SDK + emulators, Ollama / LM Studio / HuggingFace models,
        Docker / OrbStack / Colima, node / pnpm / bun / yarn caches, Python
        envs (pyenv/conda/poetry), Rust/Go/Ruby/Java, Flutter, Homebrew,
        iOS device backups, JetBrains/VS Code data, Slack/Discord/Teams,
        browser caches, Downloads, Desktop, Trash.

        Use --top N <path> for a generic "what's eating space in this folder"
        ranking of the immediate children of <path>.
        """
    )

    @Option(name: .long, help: "Minimum size in MB to display (default 100).")
    var minMb: UInt64 = 100

    @Option(name: .long, help: "Only show these categories (comma-separated, e.g. android,ai,containers).")
    var only: String = ""

    @Option(name: [.long, .customShort("n")], help: "Show top-N children under --top-root instead of the curated registry.")
    var top: Int = 0

    @Option(name: .long, help: "Root for --top (defaults to $HOME). Tilde-expanded.")
    var topRoot: String = ""

    @Flag(name: .long, help: "Include everything; ignore --min-mb threshold.")
    var all: Bool = false

    @Flag(name: .long, help: "List all known categories and exit.")
    var listCategories: Bool = false

    @Flag(name: .long, help: "Bypass the persistent index and re-measure every entry.")
    var fresh: Bool = false

    mutating func run() throws {
        if listCategories {
            print(ANSI.bold("Categories:"))
            for c in InspectCategory.allCases {
                print("  \(slug(c.rawValue))  " + ANSI.dim("(\(c.rawValue))"))
            }
            return
        }

        if top > 0 {
            try runTopN()
            return
        }
        try runCurated()
    }

    // MARK: curated registry

    private func runCurated() throws {
        let minBytes: UInt64 = all ? 0 : minMb * 1024 * 1024
        let onlyCats = parseCategories(only)
        let scanner = CachedInspectorScanner(store: IndexStore())

        print(ANSI.bold(ANSI.cyan("▎ xclean inspect — big space consumers")) + ANSI.gray(" (≥ \(minMb) MB)"))
        let started = Date()
        let findings = scanner.scan(minBytes: minBytes, only: onlyCats, forceFresh: fresh)
        let elapsed = Date().timeIntervalSince(started)

        if findings.isEmpty {
            print("")
            print(ANSI.dim("Nothing above \(minMb) MB found in the registry."))
            print(ANSI.dim("Try --all or --top 20 \(FileManager.default.homeDirectoryForCurrentUser.path)."))
            return
        }

        // Group by category in the canonical declared order.
        var grouped: [InspectCategory: [InspectFinding]] = [:]
        for f in findings { grouped[f.entry.category, default: []].append(f) }

        for cat in InspectCategory.allCases {
            guard let items = grouped[cat], !items.isEmpty else { continue }
            let catTotal = items.reduce(UInt64(0)) { $0 + $1.sizeBytes }
            print("")
            print(ANSI.bold("== \(cat.rawValue) ") + ANSI.gray("(\(ByteSize.human(catTotal)))"))
            for f in items {
                printFinding(f)
            }
        }

        // Cross-category "Top 10".
        print("")
        print(ANSI.bold("Top by size"))
        for f in findings.prefix(10) {
            let size = ByteSize.human(f.sizeBytes).padding(toLength: 11, withPad: " ", startingAt: 0)
            let cat = ANSI.gray("[\(slug(f.entry.category.rawValue))]")
            print("  " + ANSI.bold(size) + " " + f.entry.label + " " + cat)
        }

        let total = findings.reduce(UInt64(0)) { $0 + $1.sizeBytes }
        print("")
        print(ANSI.bold("Total inspected: ") + ANSI.green(ByteSize.human(total))
              + ANSI.gray(" across \(findings.count) path\(findings.count == 1 ? "" : "s") in \(String(format: "%.1fs", elapsed))"))
    }

    private func printFinding(_ f: InspectFinding) {
        let size = ByteSize.human(f.sizeBytes).padding(toLength: 11, withPad: " ", startingAt: 0)
        let label = f.entry.label.padding(toLength: 30, withPad: " ", startingAt: 0)
        let display = displayPath(f.entry.path)
        print("  " + ANSI.bold(size) + " " + label + " " + ANSI.dim(display))
        if let note = f.entry.note {
            print("              " + ANSI.dim("→ \(note)"))
        }
    }

    // MARK: top-N

    private func runTopN() throws {
        let root: URL
        if topRoot.isEmpty {
            root = FileManager.default.homeDirectoryForCurrentUser
        } else {
            let expanded = (topRoot as NSString).expandingTildeInPath
            root = URL(fileURLWithPath: expanded)
        }
        guard FS.exists(root) else {
            throw ValidationError("Root does not exist: \(root.path)")
        }

        print(ANSI.bold(ANSI.cyan("▎ xclean inspect --top \(top) \(displayPath(root))")))
        let started = Date()
        let results = InspectorScanner().topN(root: root, count: top)
        let elapsed = Date().timeIntervalSince(started)

        if results.isEmpty {
            print(ANSI.dim("No children found."))
            return
        }
        print("")
        var total: UInt64 = 0
        for (url, size) in results {
            total += size
            let s = ByteSize.human(size).padding(toLength: 11, withPad: " ", startingAt: 0)
            print("  " + ANSI.bold(s) + " " + url.lastPathComponent + " " + ANSI.dim(url.path))
        }
        print("")
        print(ANSI.bold("Top \(results.count) total: ") + ANSI.green(ByteSize.human(total))
              + ANSI.gray(" in \(String(format: "%.1fs", elapsed))"))
    }

    // MARK: helpers

    private func parseCategories(_ raw: String) -> Set<InspectCategory> {
        let names = raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        guard !names.isEmpty else { return [] }
        return Set(InspectCategory.allCases.filter { cat in
            let s = slug(cat.rawValue)
            return names.contains(s) || names.contains(cat.rawValue.lowercased())
        })
    }

    private func slug(_ s: String) -> String {
        return s.lowercased()
            .replacingOccurrences(of: " / ", with: "-")
            .replacingOccurrences(of: " & ", with: "-")
            .replacingOccurrences(of: " ", with: "-")
    }

    private func displayPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if url.path.hasPrefix(home) {
            return "~" + url.path.dropFirst(home.count)
        }
        return url.path
    }
}

// MARK: - menu

struct Menu: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "menu",
        abstract: "Launch the menu-bar app. Indexes in the background, refreshes every 30 min.",
        discussion: """
        Adds an icon to the macOS menu bar showing total cache pressure and
        the top space consumers. The indexer runs on a background queue,
        caches results to ~/Library/Application Support/xclean/index.json,
        and only re-walks paths whose root mtime changed.

        This is a long-running process. To stop it, click the menu bar icon
        and choose Quit, or send SIGINT (^C) if launched in the foreground.
        """
    )

    mutating func run() throws {
        MenuBarApp.run()
    }
}

// MARK: - reclaim

struct Reclaim: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reclaim",
        abstract: "Headless bulk cleanup. Runs every official cleanup command in sequence. Used by the auto-reclaim LaunchAgent.",
        discussion: """
        Loads the persistent index (~/Library/Application Support/xclean/),
        filters entries that have a known cleanup command, and runs them
        serially via /bin/zsh. Exits 0 on success, non-zero on any failure.

        Designed for unattended use:
          - no prompts
          - no menu
          - structured stdout / stderr for log aggregation
        """
    )

    @Flag(name: .shortAndLong, help: "Required for safety. Reclaim won't run without it.")
    var yes: Bool = false

    @Option(name: .long, help: "Minimum size in MB an entry must have to be cleaned (default 100).")
    var minMb: UInt64 = 100

    @Flag(name: .long, help: "Print what would run, don't actually do it.")
    var dryRun: Bool = false

    mutating func run() throws {
        guard yes || dryRun else {
            FileHandle.standardError.write("xclean reclaim: refusing to run without --yes\n".data(using: .utf8)!)
            throw ExitCode(2)
        }
        if !dryRun {
            try LicenseGate.requireActiveLicense()
        }

        let store = IndexStore()
        let scanner = CachedInspectorScanner(store: store)
        // Use cached sizes (fast path) — mtime check + TTL still applies.
        let findings = scanner.scan(minBytes: minMb * 1024 * 1024)
        let eligible = findings.filter { $0.entry.cleanup != nil }

        guard !eligible.isEmpty else {
            print("xclean reclaim: nothing to do (no entries with cleanup commands ≥ \(minMb) MB)")
            return
        }

        let totalPotential = eligible.reduce(UInt64(0)) { $0 + $1.sizeBytes }
        print("xclean reclaim: \(eligible.count) candidates, ~\(ByteSize.human(totalPotential)) potential")

        if dryRun {
            for (i, f) in eligible.enumerated() {
                print("  [\(i + 1)/\(eligible.count)] \(f.entry.label) — \(ByteSize.human(f.sizeBytes)) — \(f.entry.cleanup ?? "")")
            }
            return
        }

        var freed: UInt64 = 0
        var failures: [(String, String)] = []
        let started = Date()
        for (i, finding) in eligible.enumerated() {
            guard let cmd = finding.entry.cleanup else { continue }
            print("  [\(i + 1)/\(eligible.count)] \(finding.entry.label) — running: \(cmd)")
            let semaphore = DispatchSemaphore(value: 0)
            var didSucceed = false
            var stderrOut = ""
            _ = CleanupRunner.runShell(cmd) { outcome in
                switch outcome {
                case .success:
                    didSucceed = true
                case .canceled:
                    stderrOut = "canceled"
                case .failure(let m):
                    stderrOut = m
                }
                semaphore.signal()
            }
            semaphore.wait()
            if didSucceed {
                freed &+= finding.sizeBytes
            } else {
                failures.append((finding.entry.label, stderrOut))
            }
        }
        let elapsed = Date().timeIntervalSince(started)

        print("xclean reclaim: done in \(String(format: "%.1fs", elapsed))")
        print("  freed (approx): \(ByteSize.human(freed))")
        print("  successes: \(eligible.count - failures.count)/\(eligible.count)")
        if !failures.isEmpty {
            print("  failures:")
            for f in failures {
                print("    - \(f.0): \(f.1)")
            }
            throw ExitCode(1)
        }
    }
}

// MARK: - license

enum LicenseGate {
    /// Gate for destructive operations. Uses the cached license state to
    /// avoid hitting the network on every invocation; the menu app's
    /// daily heartbeat keeps the cache fresh, and `.grace` allows up to
    /// seven days of offline use after the last successful validate.
    static func requireActiveLicense() throws {
        switch LicenseManager.shared.currentState() {
        case .active, .grace:
            return
        case .unactivated:
            FileHandle.standardError.write("""
                ✗ This operation requires an active xclean license.
                  · activate:    xclean license activate <KEY>
                  · buy a key:   https://xclean-seven.vercel.app/comprar

                """.data(using: .utf8)!)
            throw ExitCode(64)
        case .invalid(let reason):
            FileHandle.standardError.write("""
                ✗ Your xclean license is invalid (\(reason)).
                  · re-activate: xclean license activate <KEY>

                """.data(using: .utf8)!)
            throw ExitCode(64)
        }
    }
}

struct License: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "license",
        abstract: "Activate, inspect, or release the xclean license on this Mac.",
        subcommands: [LicenseActivate.self, LicenseStatus.self, LicenseDeactivate.self],
        defaultSubcommand: LicenseStatus.self
    )
}

/// Bridge an async closure to a sync caller. Required because the top-level
/// `XClean` is `ParsableCommand` (sync) so that `Menu` can call `NSApp.run()`
/// on the main thread — AsyncParsableCommand schedules subcommands on a
/// non-main executor and AppKit traps when entered off the main thread.
private func runBlocking<T>(_ op: @escaping () async throws -> T) throws -> T {
    let sem = DispatchSemaphore(value: 0)
    var captured: Result<T, Error>!
    Task.detached {
        do {
            let v = try await op()
            captured = .success(v)
        } catch {
            captured = .failure(error)
        }
        sem.signal()
    }
    sem.wait()
    return try captured.get()
}

struct LicenseActivate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "activate",
        abstract: "Bind this Mac to a license key. One Mac per key."
    )

    @Argument(help: "License key (XCL-XXXX-XXXX-XXXX-XXXX).")
    var key: String

    @Option(name: .long, help: "Friendly label for this machine (default: hostname).")
    var label: String?

    mutating func run() throws {
        do {
            let theKey = key
            let theLabel = label
            let state = try runBlocking {
                try await LicenseManager.shared.activate(key: theKey, machineLabel: theLabel)
            }
            print("✓ license activated on this machine.")
            LicenseStatePrinter.print(state)
        } catch let e as LicenseManager.LicenseError {
            FileHandle.standardError.write("✗ \(e.errorDescription ?? "activation failed")\n".data(using: .utf8)!)
            throw ExitCode(1)
        }
    }
}

struct LicenseStatus: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show the current license state."
    )

    @Flag(name: .long, help: "Hit the server to refresh; default reads local cache.")
    var refresh: Bool = false

    mutating func run() throws {
        var state = LicenseManager.shared.currentState()
        if refresh && LicenseManager.shared.storedLicenseKey() != nil {
            if let fresh = try? runBlocking({ try await LicenseManager.shared.validate() }) {
                state = fresh
            }
        }
        LicenseStatePrinter.print(state)
    }
}

struct LicenseDeactivate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "deactivate",
        abstract: "Release this Mac's slot so the key can be re-activated elsewhere."
    )

    @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
    var yes: Bool = false

    mutating func run() throws {
        if !yes {
            print("Re-activations are capped at 2 per rolling 30 days. Continue? [y/N] ", terminator: "")
            let ans = readLine() ?? ""
            guard ans.lowercased().hasPrefix("y") else {
                print("aborted.")
                return
            }
        }
        do {
            try runBlocking { try await LicenseManager.shared.deactivate() }
            print("✓ this Mac is no longer activated. The license can be used on another machine.")
        } catch let e as LicenseManager.LicenseError {
            FileHandle.standardError.write("✗ \(e.errorDescription ?? "deactivate failed")\n".data(using: .utf8)!)
            throw ExitCode(1)
        }
    }
}

enum LicenseStatePrinter {
    static func print(_ state: LicenseManager.State) {
        switch state {
        case .unactivated:
            Swift.print("● not activated — run: xclean license activate <KEY>")
        case .active(let expiresAt):
            let days = max(0, Int(expiresAt.timeIntervalSinceNow / 86_400))
            Swift.print("● active — expires \(format(expiresAt)) (in \(days) days)")
        case .grace(let expiresAt, let deadline):
            let daysToExp = max(0, Int(expiresAt.timeIntervalSinceNow / 86_400))
            let daysToDeadline = max(0, Int(deadline.timeIntervalSinceNow / 86_400))
            Swift.print("⚠ offline grace — \(daysToDeadline) days left before forced re-validation")
            Swift.print("  license expires in \(daysToExp) days (\(format(expiresAt)))")
        case .invalid(let reason):
            Swift.print("✗ invalid — \(reason). Re-activate with: xclean license activate <KEY>")
        }
    }

    private static func format(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}
