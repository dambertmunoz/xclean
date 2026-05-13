import Foundation
import ArgumentParser

/// Flags shared between `scan`, `clean`, and `doctor`. They parse into a
/// `RunConfig` via `makeConfig(mode:)`.
struct SharedOptions: ParsableArguments {
    @Option(name: .long, help: "Profile: conservative, balanced (default), aggressive.")
    var profile: String = "balanced"

    @Option(name: .long, help: "Only run these plugin IDs (comma-separated). E.g. derived-data,simulators.")
    var only: String = ""

    @Option(name: .long, help: "Skip these plugin IDs (comma-separated).")
    var skip: String = ""

    @Flag(name: .long, help: "Also remove items classified as risky.")
    var includeRisky: Bool = false

    @Flag(name: .long, help: "Skip the Trash and rm immediately. Use with care.")
    var purge: Bool = false

    @Flag(name: .shortAndLong, help: "Verbose output (per-candidate paths and reasons).")
    var verbose: Bool = false

    func makeConfig(mode: Mode) throws -> RunConfig {
        guard let p = Profile.named(profile) else {
            throw ValidationError("Unknown profile: \(profile). Use conservative, balanced, or aggressive.")
        }
        let only = parseList(only)
        let skip = parseList(skip)

        return RunConfig(
            mode: mode,
            profile: p,
            onlyPlugins: only,
            skipPlugins: skip,
            purge: purge,
            includeRisky: includeRisky,
            verbose: verbose
        )
    }

    private func parseList(_ raw: String) -> Set<String> {
        return Set(raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty })
    }
}
