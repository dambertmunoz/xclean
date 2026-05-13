import Foundation

/// Plugin contract: discover cleanup candidates for one domain.
///
/// Plugins are pure observers — they describe what *could* be removed and
/// expose enough metadata (size, age, category, reason) for the central
/// `Classifier` to decide whether each item should be deleted under the
/// current `Profile`. Plugins must not mutate the file system.
protocol Cleaner {
    /// Stable identifier used in `--only` / `--skip` flags. Lowercase-dashed.
    var id: String { get }
    /// Human-readable label for reports.
    var title: String { get }
    /// Discover candidates given the run configuration.
    /// Implementations should be cheap — heavy size calculations happen here,
    /// but no deletions or external mutations.
    func discover(config: RunConfig) throws -> [Candidate]
}

/// Registry of built-in plugins. Lives outside the protocol so we can call
/// `BuiltInPlugins.all` from any context (Swift forbids `Protocol.staticMember`
/// on protocol metatypes).
enum BuiltInPlugins {
    static var all: [Cleaner] {
        return [
            DerivedDataCleaner(),
            ArchivesCleaner(),
            DeviceSupportCleaner(),
            ModuleCacheCleaner(),
            SimulatorsCleaner(),
            CocoaPodsCleaner(),
            SPMCleaner(),
            CarthageCleaner()
        ]
    }
}
