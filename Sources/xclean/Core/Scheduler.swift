import Foundation

/// Manages the LaunchAgent that runs `xclean reclaim --yes` on a schedule.
/// Install/remove are idempotent — calling `install()` twice just rewrites
/// the plist and re-bootstraps.
///
/// Default schedule: every Sunday at 03:00 local time.
enum Scheduler {

    static let label = "com.dambert.xclean.autoclean"
    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var logDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/xclean")
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    /// Installs and starts the LaunchAgent. Returns `true` on success.
    @discardableResult
    static func install(weekday: Int = 1, hour: Int = 3, minute: Int = 0) -> Bool {
        let binary = preferredBinaryPath()
        guard FileManager.default.fileExists(atPath: binary) else { return false }

        try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(binary)</string>
                <string>reclaim</string>
                <string>--yes</string>
            </array>
            <key>StartCalendarInterval</key>
            <dict>
                <key>Weekday</key><integer>\(weekday)</integer>
                <key>Hour</key><integer>\(hour)</integer>
                <key>Minute</key><integer>\(minute)</integer>
            </dict>
            <key>RunAtLoad</key>
            <false/>
            <key>StandardOutPath</key>
            <string>\(logDirectory.path)/autoclean.out.log</string>
            <key>StandardErrorPath</key>
            <string>\(logDirectory.path)/autoclean.err.log</string>
        </dict>
        </plist>
        """
        do {
            try plist.write(to: plistURL, atomically: true, encoding: .utf8)
        } catch {
            return false
        }
        // Reload regardless of previous state.
        let uid = getuid()
        _ = Shell.run("/bin/launchctl", ["bootout", "gui/\(uid)", plistURL.path])
        let r = Shell.run("/bin/launchctl", ["bootstrap", "gui/\(uid)", plistURL.path])
        return r.success
    }

    /// Stops and removes the LaunchAgent.
    @discardableResult
    static func remove() -> Bool {
        let uid = getuid()
        _ = Shell.run("/bin/launchctl", ["bootout", "gui/\(uid)", plistURL.path])
        try? FileManager.default.removeItem(at: plistURL)
        return !FileManager.default.fileExists(atPath: plistURL.path)
    }

    // MARK: - helpers

    /// Prefer the binary inside the `.app` bundle if it exists, otherwise
    /// fall back to /opt/homebrew/bin/xclean. Keeps the schedule pointing
    /// at the active install.
    private static func preferredBinaryPath() -> String {
        let candidates = [
            "/Applications/xclean.app/Contents/MacOS/xclean",
            "/opt/homebrew/bin/xclean",
            "/usr/local/bin/xclean"
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return path
        }
        return candidates[0]
    }
}
