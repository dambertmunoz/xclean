import Foundation

/// Orchestrator. Owns the plugin list, the classifier, and the executor;
/// runs discovery, prints reports, and applies removals according to the
/// run mode.
struct CleanEngine {
    let plugins: [Cleaner]
    let config: RunConfig
    let reporter: Reporter

    init(plugins: [Cleaner]? = nil,
         config: RunConfig,
         reporter: Reporter? = nil) {
        self.plugins = plugins ?? BuiltInPlugins.all
        self.config = config
        self.reporter = reporter ?? Reporter(verbose: config.verbose)
    }

    func run() throws -> ExecutionResult {
        let start = Date()
        let classifier = Classifier(profile: config.profile)
        let executor = Executor(purge: config.purge)
        var result = ExecutionResult()

        reporter.banner("xclean · profile=\(config.profile.name) · mode=\(modeLabel)")

        var totalSafe: UInt64 = 0
        var totalRisky: UInt64 = 0
        var totalKept: UInt64 = 0

        for plugin in selectedPlugins {
            let candidates: [Candidate]
            do {
                candidates = try plugin.discover(config: config)
            } catch {
                if config.verbose {
                    print(ANSI.red("warning: \(plugin.id) discovery failed: \(error)"))
                }
                continue
            }
            if candidates.isEmpty { continue }

            let pairs = candidates.map { ($0, classifier.verdict(for: $0)) }
            reporter.sectionHeader(plugin: plugin.id, title: plugin.title, candidates: candidates)
            reporter.listCandidates(pairs)

            for (c, v) in pairs {
                switch v {
                case .safe:  totalSafe  += c.sizeBytes
                case .risky: totalRisky += c.sizeBytes
                case .keep:  totalKept  += c.sizeBytes
                }
            }

            if config.mode == .scan { continue }

            // Decide which to remove.
            let removable = pairs.filter { pair in
                switch pair.1 {
                case .safe: return true
                case .risky: return config.includeRisky
                case .keep: return false
                }
            }

            if removable.isEmpty { continue }

            let shouldApply: Bool
            switch config.mode {
            case .scan:
                shouldApply = false
            case .yes:
                shouldApply = true
            case .interactive:
                let savings = removable.reduce(UInt64(0)) { $0 + $1.0.sizeBytes }
                shouldApply = reporter.confirm(
                    "Remove \(removable.count) item\(removable.count == 1 ? "" : "s") from \(plugin.title) (\(ByteSize.human(savings)))?",
                    defaultYes: true
                )
            }

            if !shouldApply { continue }

            for (c, _) in removable {
                do {
                    let freed = try executor.remove(c)
                    result.freedBytes += freed
                    result.removedCount += 1
                } catch {
                    result.failures.append((c, error))
                }
            }
        }

        if config.mode == .scan {
            reporter.dryRunFooter(totalSafe: totalSafe, totalRisky: totalRisky, totalKept: totalKept)
        } else {
            reporter.executionFooter(result, durationSec: Date().timeIntervalSince(start))
        }
        return result
    }

    // MARK: - Helpers

    private var selectedPlugins: [Cleaner] {
        return plugins.filter { p in
            if !config.onlyPlugins.isEmpty {
                return config.onlyPlugins.contains(p.id)
            }
            return !config.skipPlugins.contains(p.id)
        }
    }

    private var modeLabel: String {
        switch config.mode {
        case .scan:        return "scan (dry run)"
        case .interactive: return "interactive"
        case .yes:         return "auto-apply"
        }
    }
}
