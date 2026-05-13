import Foundation
import CoreServices

/// Watches a set of paths via FSEvents and emits a *debounced* batch of
/// dirty URLs. We use coarse latency (5s in the kernel) plus our own
/// debounce timer (default 60s) so a busy `~/.gradle` doesn't trigger a
/// re-measure every second while a build is running.
///
/// Memory + CPU footprint:
///   * One FSEventStream — kernel handles event coalescing for us.
///   * A small `Set<String>` of dirty paths between debounce ticks.
///   * No retained file URLs, no per-event allocations on the hot path.
final class FSWatcher {

    /// Called on the main queue with the URLs whose subtree changed.
    var onChanged: (([URL]) -> Void)?

    private let watchedPaths: [URL]
    private let debounceSeconds: TimeInterval
    private var stream: FSEventStreamRef?
    private var dirty = Set<String>()
    private let dirtyLock = NSLock()
    private var debounceWorkItem: DispatchWorkItem?

    init(paths: [URL], debounceSeconds: TimeInterval = 60) {
        self.watchedPaths = paths
        self.debounceSeconds = debounceSeconds
    }

    deinit { stop() }

    // MARK: - lifecycle

    func start() {
        guard stream == nil else { return }
        guard !watchedPaths.isEmpty else { return }

        // FSEvents wants CFArray<CFString>. We hand it the existing paths
        // (missing ones are harmless — FSEvents ignores them).
        let pathStrings = watchedPaths.map { $0.path } as CFArray

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags: FSEventStreamCreateFlags =
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes
                                     | kFSEventStreamCreateFlagFileEvents
                                     | kFSEventStreamCreateFlagIgnoreSelf
                                     | kFSEventStreamCreateFlagNoDefer)

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            FSWatcher.callback,
            &context,
            pathStrings,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            5.0,
            flags
        ) else {
            return
        }

        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(stream)
        self.stream = stream
    }

    func stop() {
        guard let stream = stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    // MARK: - callback plumbing

    private static let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, _, _ in
        guard let info = info else { return }
        let watcher = Unmanaged<FSWatcher>.fromOpaque(info).takeUnretainedValue()

        let pathsArray = unsafeBitCast(eventPaths, to: CFArray.self) as? [String] ?? []
        guard !pathsArray.isEmpty else { return }

        watcher.absorb(eventPaths: pathsArray, count: numEvents)
    }

    /// Maps incoming event paths onto our watched roots, then schedules a
    /// single debounced flush. Map step keeps the dirty set small: even if
    /// thousands of files change inside `~/.gradle`, we only mark
    /// `~/.gradle` once.
    private func absorb(eventPaths: [String], count: Int) {
        dirtyLock.lock()
        for raw in eventPaths {
            if let root = matchWatchedRoot(for: raw) {
                dirty.insert(root)
            }
        }
        dirtyLock.unlock()
        scheduleFlush()
    }

    private func matchWatchedRoot(for path: String) -> String? {
        for root in watchedPaths {
            let rootPath = root.path
            if path == rootPath || path.hasPrefix(rootPath + "/") {
                return rootPath
            }
        }
        return nil
    }

    private func scheduleFlush() {
        // Cancel any pending flush; reschedule for `debounceSeconds` ahead.
        // Coalesces bursts of activity into one refresh per quiet period.
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.flush()
        }
        debounceWorkItem = work
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + debounceSeconds,
            execute: work
        )
    }

    private func flush() {
        dirtyLock.lock()
        let snapshot = Array(dirty)
        dirty.removeAll(keepingCapacity: true)
        dirtyLock.unlock()

        guard !snapshot.isEmpty else { return }
        let urls = snapshot.map { URL(fileURLWithPath: $0) }
        DispatchQueue.main.async { [weak self] in
            self?.onChanged?(urls)
        }
    }
}
