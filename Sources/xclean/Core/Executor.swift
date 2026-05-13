import Foundation

/// Tracks what was removed during a single run.
struct ExecutionResult {
    var freedBytes: UInt64 = 0
    var removedCount: Int = 0
    var failures: [(Candidate, Error)] = []
}

enum ExecutorError: Error, CustomStringConvertible {
    case trashFailed(URL, underlying: Error)
    case simctlFailed(stderr: String)
    case commandFailed(String, stderr: String)

    var description: String {
        switch self {
        case .trashFailed(let url, let err):
            return "trash failed for \(url.path): \(err)"
        case .simctlFailed(let stderr):
            return "simctl failed: \(stderr)"
        case .commandFailed(let cmd, let stderr):
            return "\(cmd) failed: \(stderr)"
        }
    }
}

/// Performs the actual mutation. The only component that touches the FS.
struct Executor {
    let purge: Bool

    func remove(_ c: Candidate) throws -> UInt64 {
        switch c.removal {
        case .path(let url):
            try removePath(url)
            return c.sizeBytes

        case .simulatorDevice(let udid, _):
            let r = Shell.xcrun(["simctl", "delete", udid])
            if !r.success {
                throw ExecutorError.simctlFailed(stderr: r.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return c.sizeBytes

        case .simulatorRuntime(let identifier, _):
            let r = Shell.xcrun(["simctl", "runtime", "delete", identifier])
            if !r.success {
                throw ExecutorError.simctlFailed(stderr: r.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return c.sizeBytes

        case .command(let launchPath, let args):
            let r = Shell.run(launchPath, args)
            if !r.success {
                throw ExecutorError.commandFailed("\(launchPath) \(args.joined(separator: " "))",
                                                  stderr: r.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return c.sizeBytes
        }
    }

    private func removePath(_ url: URL) throws {
        guard FS.exists(url) else { return }
        if purge {
            do {
                try FS.fm.removeItem(at: url)
            } catch {
                throw ExecutorError.trashFailed(url, underlying: error)
            }
        } else {
            do {
                var resulting: NSURL?
                try FS.fm.trashItem(at: url, resultingItemURL: &resulting)
            } catch {
                throw ExecutorError.trashFailed(url, underlying: error)
            }
        }
    }
}
