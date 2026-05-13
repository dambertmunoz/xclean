import Foundation

/// On Unix, `rm` only unlinks. Bytes stay on disk until the **last open
/// file descriptor** to those inodes is closed. When a cleanup nukes a
/// path that long-running background processes still have files open in
/// (MCP servers reading wheel files, IDE indexers, etc.), the user sees
/// "X GB freed" in the menu but `df` doesn't move.
///
/// `GhostFileDetector` finds those processes via `lsof` so the UI can
/// offer to restart them.
enum GhostFileDetector {

    struct Holder: Hashable {
        let pid: Int32
        let command: String
    }

    /// Returns the processes holding deleted files under `directory`.
    /// Empty when nobody is holding anything (the happy path).
    ///
    /// Uses `lsof -nP -F pcn` — the `-F` machine-readable format is faster
    /// to parse than the default text columns. The whole call usually
    /// finishes in well under a second on a typical Mac.
    static func holdersOfDeletedFiles(in directory: URL) -> [Holder] {
        let prefix = directory.path
        // -n  : no DNS · -P : no port lookup · -F pcn : pid/command/name records
        let r = Shell.run("/usr/sbin/lsof", ["-nP", "-F", "pcn"])
        guard r.success || !r.stdout.isEmpty else { return [] }

        var holders = Set<Holder>()
        var currentPID: Int32 = -1
        var currentCmd = ""

        for line in r.stdout.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let kind = line.first else { continue }
            let tail = line.dropFirst()
            switch kind {
            case "p":
                currentPID = Int32(tail) ?? -1
                currentCmd = ""
            case "c":
                currentCmd = String(tail)
            case "n":
                let name = String(tail)
                // We want files that (a) live under the cleaned directory
                // and (b) are unlinked. lsof exposes the unlinked state in
                // two ways depending on macOS version: "(deleted)" suffix,
                // or path ending in " (deleted)". Catch both.
                guard name.hasPrefix(prefix) else { continue }
                let isDeleted = name.contains("(deleted)")
                    || name.hasSuffix(" (deleted)")
                if isDeleted && currentPID > 0 {
                    holders.insert(Holder(pid: currentPID, command: currentCmd))
                }
            default:
                break
            }
        }
        return holders.sorted { $0.pid < $1.pid }
    }

    /// Sends SIGTERM to every holder. Cleaner than SIGKILL — long-running
    /// MCP servers / dev tools handle SIGTERM gracefully and the parent
    /// (Claude Code, your shell, …) typically respawns them on demand.
    @discardableResult
    static func terminate(_ holders: [Holder]) -> Int {
        var killed = 0
        for h in holders where h.pid > 0 {
            if kill(h.pid, SIGTERM) == 0 { killed += 1 }
        }
        return killed
    }
}
