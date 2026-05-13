import Foundation

/// Why this candidate is a cleanup target.
enum CleanCategory: String, CaseIterable, Codable {
    case age         // not touched in a long time
    case orphan      // backing project/source no longer exists
    case corruption  // unavailable / inconsistent state
    case duplicate   // older version of something we still need
    case generic     // pure cache, safe to wipe entirely
}

/// How to actually remove this candidate.
enum RemovalKind {
    /// Move a path on disk to ~/.Trash (or rm if --purge).
    case path(URL)
    /// Delete a CoreSimulator device by UDID.
    case simulatorDevice(udid: String, name: String)
    /// Delete a CoreSimulator runtime by identifier.
    case simulatorRuntime(identifier: String, name: String)
    /// Run an arbitrary command (rarely used; kept for extensibility).
    case command(launchPath: String, args: [String])
}

/// A single item that a plugin proposes to clean up.
struct Candidate {
    let cleanerID: String
    let displayName: String
    let sizeBytes: UInt64
    let lastUsed: Date?
    let category: CleanCategory
    let detail: String
    let removal: RemovalKind

    /// Convenience access to the on-disk path, if any.
    var path: URL? {
        if case let .path(url) = removal { return url }
        return nil
    }
}
