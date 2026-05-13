import Foundation

enum Mode {
    case scan          // dry-run, report only
    case interactive   // ask per category before deleting
    case yes           // delete everything that classifies as `.safe`
}

/// Runtime configuration for one invocation. Composed in CLI from flags.
struct RunConfig {
    let mode: Mode
    let profile: Profile
    /// If non-empty, only these plugin IDs run.
    let onlyPlugins: Set<String>
    /// Plugin IDs to skip even if `onlyPlugins` is empty.
    let skipPlugins: Set<String>
    /// If true, `rm` candidates instead of moving to Trash.
    let purge: Bool
    /// If true, include `.risky` candidates in deletions.
    let includeRisky: Bool
    let verbose: Bool

    static let scanDefaults = RunConfig(
        mode: .scan,
        profile: .balanced,
        onlyPlugins: [],
        skipPlugins: [],
        purge: false,
        includeRisky: false,
        verbose: false
    )
}
