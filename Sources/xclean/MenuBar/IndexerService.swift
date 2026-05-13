import Foundation

/// Owns the background scan loop and broadcasts results to the UI on the
/// main queue. Also samples disk capacity, ticks the capacity history,
/// and integrates the FSEvents watcher for reactive refreshes.
///
/// Refresh paths:
/// * `refreshNow()`           — full re-scan (mtime-aware; very cheap when
///                              nothing changed).
/// * `refreshEntry(path:)`    — re-measure a single path. Used after a
///                              cleanup so the menu reflects the new size
///                              in < 1 second.
/// * FSEvents callback        — debounced 60s; refreshes only paths whose
///                              subtree changed.
final class IndexerService {
    enum State: Equatable {
        case idle
        case indexing
        case running(label: String, startedAt: Date)
        case ready(Date)
    }

    var onFindings: (([InspectFinding]) -> Void)?
    var onState: ((State) -> Void)?
    var onCapacity: ((DiskCapacity, _ sparkline: String?) -> Void)?

    let store: IndexStore
    let history: HistoryStore
    let capacityHistory: CapacityHistory

    private let scanner: CachedInspectorScanner
    private let refreshInterval: TimeInterval
    private let workQueue = DispatchQueue(label: "xclean.indexer", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var inFlight = false
    private let inFlightLock = NSLock()
    private var watcher: FSWatcher?

    init(refreshInterval: TimeInterval = 30 * 60) {
        self.store = IndexStore()
        self.history = HistoryStore()
        self.capacityHistory = CapacityHistory()
        self.scanner = CachedInspectorScanner(store: store)
        self.refreshInterval = refreshInterval
    }

    // MARK: - public entry points

    func start() {
        publishCapacity()
        publishFromStore()
        refreshNow()
        startFSWatcher()

        let t = DispatchSource.makeTimerSource(queue: workQueue)
        t.schedule(deadline: .now() + refreshInterval, repeating: refreshInterval)
        t.setEventHandler { [weak self] in self?.refreshNow() }
        t.resume()
        self.timer = t
    }

    func refreshNow() {
        inFlightLock.lock()
        guard !inFlight else { inFlightLock.unlock(); return }
        inFlight = true
        inFlightLock.unlock()

        publish(state: .indexing)
        workQueue.async { [weak self] in
            guard let self = self else { return }
            let minBytes = Preferences.shared.effectiveMinBytes
            let findings = self.scanner.scan(minBytes: minBytes)
            self.publish(findings: findings)
            self.publishCapacity()
            self.publish(state: .ready(Date()))
            self.inFlightLock.lock(); self.inFlight = false; self.inFlightLock.unlock()
        }
    }

    func refreshEntry(path: URL) {
        workQueue.async { [weak self] in
            guard let self = self else { return }
            if !FS.exists(path) {
                self.store.remove(path: path.path)
            } else {
                let mtime = SizeMeasurer.mtime(of: path)
                let size = SizeMeasurer.size(of: path)
                let prevSize = self.store.get(path.path)?.sizeBytes
                let row = IndexEntry(
                    path: path.path,
                    sizeBytes: size,
                    previousSizeBytes: prevSize,
                    rootMtime: mtime,
                    computedAt: Date()
                )
                self.store.put(row)
            }
            self.store.save()
            self.publishFromStore()
            self.publishCapacity()
        }
    }

    func setRunning(label: String, startedAt: Date = Date()) {
        publish(state: .running(label: label, startedAt: startedAt))
    }

    /// Re-emit the current best-known snapshot. Used after toggling prefs
    /// (compact mode, etc.) to update the filter without re-scanning.
    func republish() {
        workQueue.async { [weak self] in
            self?.publishFromStore()
        }
    }

    /// Walks default project roots, finds artifact dirs, and triggers a
    /// refresh so the new entries get sized. `completion` is called with
    /// the number of artifacts found.
    func scanProjects(completion: @escaping (Int) -> Void) {
        publish(state: .running(label: "Scanning projects…", startedAt: Date()))
        workQueue.async { [weak self] in
            guard let self = self else { return }
            let found = ProjectScanner.scan()
            DispatchQueue.main.async { completion(found.count) }
            // Drop any stale rows for paths that no longer exist (e.g. user
            // deleted a project) — they'd otherwise clutter the menu.
            self.pruneStoreToRegistry()
            self.refreshNow()
        }
    }

    /// Forces the FSWatcher to widen its watch set when new project paths
    /// were added. Call after a successful `scanProjects`.
    func reconfigureFSWatcher() {
        watcher?.stop()
        startFSWatcher()
    }

    private func pruneStoreToRegistry() {
        let valid = Set(InspectorRegistry.all.map { $0.path.path })
        let cached = store.allSortedBySize().map { $0.path }
        for p in cached where !valid.contains(p) {
            store.remove(path: p)
        }
        store.save()
    }

    // MARK: - FSEvents

    private func startFSWatcher() {
        let paths = InspectorRegistry.all
            .map { $0.path }
            .filter { FS.exists($0) }
        let w = FSWatcher(paths: paths, debounceSeconds: 60)
        w.onChanged = { [weak self] urls in
            // Refresh each dirty path. Cheap thanks to the mtime cache.
            for url in urls {
                self?.refreshEntry(path: url)
            }
        }
        w.start()
        self.watcher = w
    }

    // MARK: - publish helpers

    private func publishFromStore() {
        let rows = store.allSortedBySize()
        let minBytes = Preferences.shared.effectiveMinBytes
        let findings = rows.compactMap { row -> InspectFinding? in
            guard let entry = InspectorRegistry.all.first(where: { $0.path.path == row.path }) else { return nil }
            guard row.sizeBytes >= minBytes else { return nil }
            return InspectFinding(entry: entry, sizeBytes: row.sizeBytes, previousSizeBytes: row.previousSizeBytes)
        }.sortedBySafetyThenSize()
        if !findings.isEmpty {
            publish(findings: findings)
            let newest = rows.map { $0.computedAt }.max() ?? Date()
            publish(state: .ready(newest))
        }
    }

    private func publish(findings: [InspectFinding]) {
        DispatchQueue.main.async { [weak self] in
            self?.onFindings?(findings)
        }
    }

    private func publish(state: State) {
        DispatchQueue.main.async { [weak self] in
            self?.onState?(state)
        }
    }

    private func publishCapacity() {
        guard let cap = DiskInspector.current() else { return }
        // Persist hourly so the sparkline has data points.
        capacityHistory.recordIfDue(availableBytes: cap.availableBytes)
        let spark = capacityHistory.sparkline(width: 12)
        // Side-effect: notify on degradation.
        ThresholdNotifier.evaluate(cap)
        DispatchQueue.main.async { [weak self] in
            self?.onCapacity?(cap, spark)
        }
    }
}
