import Foundation

/// Pretty terminal output for scan results, prompts, and execution summaries.
/// Pure presentation — no FS access, no decisions.
struct Reporter {
    let verbose: Bool

    // MARK: - Headers

    func banner(_ s: String) {
        print(ANSI.bold(ANSI.cyan("▎ " + s)))
    }

    func sectionHeader(plugin id: String, title: String, candidates: [Candidate]) {
        let safeSize = candidates.reduce(into: UInt64(0)) { $0 += $1.sizeBytes }
        let count = candidates.count
        print("")
        print(ANSI.bold("== \(title) ") + ANSI.gray("(\(id)) ") + ANSI.bold(ByteSize.human(safeSize)) + ANSI.gray(" • \(count) item\(count == 1 ? "" : "s")"))
    }

    // MARK: - Per-candidate listing

    func listCandidates(_ candidates: [(Candidate, Verdict)]) {
        for (c, v) in candidates {
            let badge = verdictBadge(v)
            let cat = ANSI.gray("[\(c.category.rawValue)]")
            let size = ANSI.bold(ByteSize.human(c.sizeBytes).padding(toLength: 10, withPad: " ", startingAt: 0))
            let age = c.lastUsed.map { ANSI.gray("\(Classifier.daysSince($0))d") } ?? ANSI.gray("—")
            print("  \(badge) \(size) \(cat) \(c.displayName) \(age)")
            if verbose {
                print("        \(ANSI.dim(c.detail))")
                if let p = c.path {
                    print("        \(ANSI.dim(p.path))")
                }
            }
        }
    }

    private func verdictBadge(_ v: Verdict) -> String {
        switch v {
        case .safe:  return ANSI.green("●")
        case .risky: return ANSI.yellow("●")
        case .keep:  return ANSI.gray("○")
        }
    }

    // MARK: - Summaries

    func dryRunFooter(totalSafe: UInt64, totalRisky: UInt64, totalKept: UInt64) {
        print("")
        print(ANSI.bold("Summary"))
        print("  " + ANSI.green("● safe   ") + ByteSize.human(totalSafe))
        print("  " + ANSI.yellow("● risky  ") + ByteSize.human(totalRisky)
              + ANSI.gray("  (use --include-risky to remove)"))
        print("  " + ANSI.gray("○ kept   ") + ByteSize.human(totalKept))
        print("")
        print(ANSI.dim("Dry run. Re-run with `xclean clean` to apply."))
    }

    func executionFooter(_ result: ExecutionResult, durationSec: Double) {
        print("")
        print(ANSI.bold("Done."))
        print("  freed:   " + ANSI.green(ByteSize.human(result.freedBytes)))
        print("  removed: \(result.removedCount) item\(result.removedCount == 1 ? "" : "s")")
        if !result.failures.isEmpty {
            print("  " + ANSI.red("failures: \(result.failures.count)"))
            for (c, err) in result.failures {
                print("    " + ANSI.red("✗") + " \(c.displayName) — \(err)")
            }
        }
        print("  took:    " + ANSI.gray(String(format: "%.1fs", durationSec)))
    }

    // MARK: - Prompts

    func confirm(_ message: String, defaultYes: Bool = false) -> Bool {
        let suffix = defaultYes ? "[Y/n]" : "[y/N]"
        print(ANSI.bold(message) + " " + ANSI.gray(suffix) + " ", terminator: "")
        guard let line = readLine() else { return defaultYes }
        let answer = line.trimmingCharacters(in: .whitespaces).lowercased()
        if answer.isEmpty { return defaultYes }
        return answer == "y" || answer == "yes"
    }
}
