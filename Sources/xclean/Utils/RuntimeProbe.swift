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

    /// True when this process can enumerate a third-party container without
    /// hitting the macOS Sonoma+ "App Management" TCC prompt. The check
    /// reads the contents of `~/Library/Containers/<probe>/Data` — if at
    /// least one of the probed Apple-vended containers returns its child
    /// list, the App Management permission is in effect (or FDA covers it).
    ///
    /// Both FDA and the dedicated App Management toggle satisfy this probe
    /// because both grant access to the same `kTCCServiceSystemPolicyAppData`
    /// surface. The probe is read-only — listing a directory does not
    /// raise the system prompt; only WRITE operations would.
    static func hasAppManagementAccess() -> Bool {
        // FDA implies App Management — fast path.
        if hasFullDiskAccess() { return true }
        let fm = FileManager.default
        let containers = NSHomeDirectory() + "/Library/Containers"
        // Pick a small set of containers we expect to exist on most Macs.
        let probes = [
            "com.apple.AppStore",
            "com.apple.Notes",
            "com.apple.MobileSMS",
            "com.apple.Safari",
            "com.apple.weather",
        ]
        for bundle in probes {
            let dataPath = containers + "/" + bundle + "/Data"
            if fm.fileExists(atPath: dataPath) {
                let kids = (try? fm.contentsOfDirectory(atPath: dataPath)) ?? []
                if !kids.isEmpty { return true }
            }
        }
        return false
    }
}
