import Foundation

/// Sequentially runs the official cleanup command for every finding that
/// has one. **Serial** by design: parallel cleanups would thrash the
/// filesystem (`uv cache clean` + `npm cache clean` competing for the same
/// SSD bandwidth), and per-tool commands sometimes touch shared metadata.
///
/// Lifecycle:
///   * `run(findings:)` queues the eligible findings and starts step 1
///   * each step updates `onProgress`
///   * on completion (or full failure), `onComplete` fires
///   * `cancel()` aborts the active step and stops the queue
///
/// We don't try to measure freed bytes here — the caller refreshes the
/// affected entries afterwards and the delta is derived from the index.
final class BulkCleaner {

    struct Progress {
        let completed: Int
        let total: Int
        let currentLabel: String
        let currentCommand: String
        let bytesFreedSoFar: UInt64
    }

    struct Outcome {
        let completed: Int
        let total: Int
        let bytesFreed: UInt64
        let failures: [(label: String, message: String)]
        let canceled: Bool
    }

    var onProgress: ((Progress) -> Void)?
    var onComplete: ((Outcome) -> Void)?
    /// Called after each step finishes so the caller can re-measure that
    /// specific path and update the UI quickly.
    var onStepFinished: ((InspectFinding, UInt64) -> Void)?

    private var queue: [InspectFinding] = []
    private var index: Int = 0
    private var bytesFreed: UInt64 = 0
    private var failures: [(String, String)] = []
    private var canceled: Bool = false
    private var currentJob: RunningJob?
    private let stateLock = NSLock()

    /// Filter, queue, and start. Findings without a `cleanup` command are
    /// skipped silently.
    func run(_ findings: [InspectFinding]) {
        let eligible = findings.filter { $0.entry.cleanup != nil }
        stateLock.lock()
        queue = eligible
        index = 0
        bytesFreed = 0
        failures = []
        canceled = false
        stateLock.unlock()

        guard !eligible.isEmpty else {
            onComplete?(Outcome(completed: 0, total: 0, bytesFreed: 0, failures: [], canceled: false))
            return
        }
        runNext()
    }

    func cancel() {
        stateLock.lock()
        canceled = true
        let job = currentJob
        stateLock.unlock()
        job?.cancel()
    }

    // MARK: - internals

    private func runNext() {
        stateLock.lock()
        if canceled || index >= queue.count {
            let outcome = Outcome(
                completed: index,
                total: queue.count,
                bytesFreed: bytesFreed,
                failures: failures,
                canceled: canceled
            )
            stateLock.unlock()
            onComplete?(outcome)
            return
        }
        let finding = queue[index]
        let total = queue.count
        let completed = index
        let freedSoFar = bytesFreed
        stateLock.unlock()

        guard let command = finding.entry.cleanup else {
            // shouldn't happen due to filter, but advance safely
            stateLock.lock(); index += 1; stateLock.unlock()
            runNext()
            return
        }

        onProgress?(Progress(
            completed: completed,
            total: total,
            currentLabel: finding.entry.label,
            currentCommand: command,
            bytesFreedSoFar: freedSoFar
        ))

        let priorSize = finding.sizeBytes
        let job = CleanupRunner.runShell(command) { [weak self] outcome in
            guard let self = self else { return }

            self.stateLock.lock()
            self.currentJob = nil
            switch outcome {
            case .success:
                // Conservative estimate: assume we freed everything the
                // entry previously held. The caller refreshes immediately
                // after and the real delta lands in the index.
                self.bytesFreed &+= priorSize
            case .canceled:
                self.canceled = true
            case .failure(let message):
                self.failures.append((finding.entry.label, message))
            }
            self.index += 1
            let estimatedFreed = (outcome.isSuccess) ? priorSize : 0
            self.stateLock.unlock()

            self.onStepFinished?(finding, estimatedFreed)
            // Yield a tick so the UI can refresh between steps.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.runNext()
            }
        }
        stateLock.lock(); currentJob = job; stateLock.unlock()
    }
}

private extension CleanupRunner.Outcome {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
