import Foundation

/// Handle for an in-flight cleanup. The caller stores this and calls
/// `cancel()` to abort. `cancel()` sends SIGTERM; the completion will still
/// fire (with a "canceled by user" failure).
final class RunningJob {
    private let process: Process
    private(set) var canceled: Bool = false
    private let lock = NSLock()

    init(_ process: Process) { self.process = process }

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        guard !canceled else { return }
        canceled = true
        if process.isRunning {
            process.terminate()
        }
    }

    var isCanceled: Bool {
        lock.lock(); defer { lock.unlock() }
        return canceled
    }
}

/// Executes destructive actions for inspect findings.
///
/// Two operations:
///   * **runShell** — run a shell line via `/bin/zsh -c` with the user's
///     resolved login PATH injected. Returns a `RunningJob` so the UI can
///     cancel it (e.g. a hung `uv cache clean` that's churning through a
///     hundred thousand small files).
///   * **trash** — `FileManager.trashItem`. Effectively a rename on the
///     same volume, so it's fast and not cancellable.
///
/// **Pipe drainage.** Stdout and stderr are read on separate background
/// queues so the child never blocks waiting for us to drain the other pipe
/// (the macOS pipe buffer is ~64 KB).
enum CleanupRunner {

    enum Outcome {
        case success(stdout: String)
        case canceled
        case failure(message: String)
    }

    // MARK: - run

    /// Runs `line` via zsh -c with PATH set to the user's login PATH.
    /// Returns a `RunningJob` for cancellation.
    @discardableResult
    static func runShell(_ line: String, completion: @escaping (Outcome) -> Void) -> RunningJob {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", line]
        process.environment = UserPath.augmentedEnvironment

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let job = RunningJob(process)

        DispatchQueue.global(qos: .userInitiated).async {
            var outData = Data()
            var errData = Data()
            let group = DispatchGroup()
            let q = DispatchQueue.global(qos: .userInitiated)

            group.enter()
            q.async {
                outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }
            group.enter()
            q.async {
                errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }

            do {
                try process.run()
            } catch {
                DispatchQueue.main.async { completion(.failure(message: "\(error)")) }
                return
            }

            process.waitUntilExit()
            group.wait()

            let outcome: Outcome
            if job.isCanceled {
                outcome = .canceled
            } else if process.terminationStatus == 0 {
                outcome = .success(stdout: String(data: outData, encoding: .utf8) ?? "")
            } else {
                let stderr = (String(data: errData, encoding: .utf8) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                outcome = .failure(message: stderr.isEmpty
                                   ? "command exited with status \(process.terminationStatus)"
                                   : stderr)
            }

            DispatchQueue.main.async { completion(outcome) }
        }

        return job
    }

    /// Move a path to the user's Trash. Reversible via Finder → Put Back.
    static func trash(_ url: URL, completion: @escaping (Outcome) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                var resultingURL: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
                DispatchQueue.main.async {
                    completion(.success(stdout: resultingURL?.path ?? url.path))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(message: "\(error)"))
                }
            }
        }
    }
}
