import Foundation

/// Cheap, side-effect-free runtime checks used to decide whether to offer a
/// cleanup command. Each probe is a single `stat`-equivalent call — fast
/// enough to re-run on every menu refresh.
enum RuntimeProbe {

    /// True when the Docker daemon socket is present. Docker Desktop
    /// removes the socket file on quit, so existence is a reliable proxy
    /// for "the daemon is up and answering API calls".
    static func isDockerDaemonRunning() -> Bool {
        let candidates = [
            "/var/run/docker.sock",
            NSHomeDirectory() + "/.docker/run/docker.sock",
            NSHomeDirectory() + "/.colima/default/docker.sock",
            NSHomeDirectory() + "/.orbstack/run/docker.sock"
        ]
        return candidates.contains { FileManager.default.fileExists(atPath: $0) }
    }

    /// True when there is at least one Homebrew installation root present.
    /// Useful for guarding `brew cleanup` if we ever surface it conditionally.
    static func isHomebrewInstalled() -> Bool {
        let roots = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        return roots.contains { FileManager.default.fileExists(atPath: $0) }
    }

    /// True when this process can read the TCC database — the canonical
    /// proxy for "we have Full Disk Access". We only attempt `open()` for
    /// read; we never look at the contents. Returns false if the kernel
    /// blocks us (no FDA) or the file isn't there for any other reason.
    ///
    /// Use this to drive UI hints in the Preferences submenu and to skip
    /// the FDA prompt when the user already granted it.
    static func hasFullDiskAccess() -> Bool {
        let path = NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db"
        let fd = Darwin.open(path, O_RDONLY)
        guard fd >= 0 else { return false }
        Darwin.close(fd)
        return true
    }
}
