import Foundation

/// Resolves the user's interactive zsh login PATH **once** per process and
/// caches the result. Anything launched by `launchd` (our LaunchAgent
/// included) inherits a stripped-down environment without `/opt/homebrew`,
/// `~/.local/bin`, etc., so we need this single source of truth for:
///
/// * spawning cleanup subprocesses (CleanupRunner)
/// * checking whether a CLI tool is installed (Inspector pre-flight)
///
/// The lookup is bounded:
///   * one `zsh -il -c "printf …"` at first access
///   * fallback list of common install roots if the probe fails
///   * tool availability checks are memoised per-tool name
enum UserPath {

    // MARK: - resolved PATH

    /// `PATH` string formatted as colon-separated dirs.
    static let resolved: String = computeResolvedPath()

    private static func computeResolvedPath() -> String {
        let marker = "@@@XCLEAN_PATH@@@"
        let r = Shell.run("/bin/zsh", ["-il", "-c", "printf '%s%s\\n' '\(marker)' \"$PATH\""])
        if r.success, let extracted = extract(after: marker, in: r.stdout) {
            return extracted
        }
        let home = NSHomeDirectory()
        var paths = [
            "/opt/homebrew/bin", "/opt/homebrew/sbin",
            "/usr/local/bin", "/usr/local/sbin",
            "\(home)/.local/bin",
            "\(home)/bin",
            "\(home)/.cargo/bin",
            "\(home)/.bun/bin",
            "\(home)/.deno/bin",
            "\(home)/.pyenv/shims",
            "\(home)/.rbenv/shims",
            "\(home)/.fnm/aliases/default/bin",
            "\(home)/go/bin",
            "/usr/bin", "/bin", "/usr/sbin", "/sbin"
        ]
        if let current = ProcessInfo.processInfo.environment["PATH"] {
            paths.append(current)
        }
        return paths.joined(separator: ":")
    }

    private static func extract(after marker: String, in text: String) -> String? {
        guard let r = text.range(of: marker) else { return nil }
        let tail = text[r.upperBound...]
        if let nl = tail.firstIndex(of: "\n") {
            let v = tail[..<nl].trimmingCharacters(in: .whitespacesAndNewlines)
            return v.isEmpty ? nil : v
        }
        let v = tail.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

    // MARK: - environment helper

    /// Process environment with our resolved PATH injected. Use for any
    /// subprocess that needs to find user tools.
    static var augmentedEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = resolved
        return env
    }

    // MARK: - tool availability

    private static var toolCache: [String: Bool] = [:]
    private static let toolCacheLock = NSLock()

    /// True if there is an executable file named `tool` somewhere in
    /// `resolved`. The decision is memoised — tool installs during the
    /// app's lifetime are rare and a stale negative is acceptable.
    static func contains(tool: String) -> Bool {
        toolCacheLock.lock()
        if let cached = toolCache[tool] {
            toolCacheLock.unlock()
            return cached
        }
        toolCacheLock.unlock()

        let fm = FileManager.default
        var found = false
        for dir in resolved.split(separator: ":") {
            let p = String(dir) + "/" + tool
            if fm.isExecutableFile(atPath: p) { found = true; break }
        }

        toolCacheLock.lock()
        toolCache[tool] = found
        toolCacheLock.unlock()
        return found
    }
}
