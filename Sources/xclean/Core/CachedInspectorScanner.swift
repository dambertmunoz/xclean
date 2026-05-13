import Foundation

/// Wraps `InspectorRegistry` with a persistent index. The first scan is full
/// cost; subsequent scans skip any entry whose root `mtime` matches what we
/// previously recorded — turning a multi-second walk into one `stat`.
///
/// A hard TTL backstops the staleness check so we eventually re-measure even
/// when a cache directory's root `mtime` is sticky (e.g. some tools update
/// inner files but never touch the root).
struct CachedInspectorScanner {
    let store: IndexStore
    /// Maximum age of a cached entry before we re-walk regardless of mtime.
    let ttl: TimeInterval

    init(store: IndexStore, ttl: TimeInterval = 2 * 3600) {
        self.store = store
        self.ttl = ttl
    }

    /// Concurrency cap. Too many parallel `du` processes hurt I/O.
    private var maxConcurrency: Int {
        max(2, min(ProcessInfo.processInfo.activeProcessorCount, 8))
    }

    /// Scan and return findings.
    ///
    /// - Parameters:
    ///   - minBytes: hide entries smaller than this (default: 0 = include all).
    ///   - only: optional filter by `InspectCategory`.
    ///   - forceFresh: bypass the cache and remeasure every entry.
    ///   - onProgress: per-finding callback (called as each entry completes).
    func scan(
        minBytes: UInt64 = 0,
        only: Set<InspectCategory> = [],
        forceFresh: Bool = false,
        onProgress: ((InspectFinding) -> Void)? = nil
    ) -> [InspectFinding] {

        let entries = only.isEmpty
            ? InspectorRegistry.all
            : InspectorRegistry.all.filter { only.contains($0.category) }

        // Phase 1 — fast triage: which entries are cache-valid?
        let now = Date()
        var pending: [(Int, InspectEntry)] = []
        var sizes = [UInt64?](repeating: nil, count: entries.count)
        var previousSizes = [UInt64?](repeating: nil, count: entries.count)

        for (i, e) in entries.enumerated() {
            guard FS.exists(e.path) else { continue }
            let currentMtime = SizeMeasurer.mtime(of: e.path)
            let cached = store.get(e.path.path)

            if !forceFresh, let cached = cached {
                let mtimeMatches = sameSecond(cached.rootMtime, currentMtime)
                let fresh = now.timeIntervalSince(cached.computedAt) < ttl
                if mtimeMatches && fresh {
                    sizes[i] = cached.sizeBytes
                    previousSizes[i] = cached.previousSizeBytes
                    continue
                }
            }
            pending.append((i, e))
        }

        // Phase 2 — measure stale entries in parallel, capped to maxConcurrency.
        if !pending.isEmpty {
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = maxConcurrency
            let lock = NSLock()
            for (i, e) in pending {
                queue.addOperation {
                    let mtime = SizeMeasurer.mtime(of: e.path)
                    let size = SizeMeasurer.size(of: e.path)
                    // Carry the prior size forward so the UI can render
                    // deltas across scans.
                    let prevSize = self.store.get(e.path.path)?.sizeBytes
                    let entry = IndexEntry(
                        path: e.path.path,
                        sizeBytes: size,
                        previousSizeBytes: prevSize,
                        rootMtime: mtime,
                        computedAt: Date()
                    )
                    self.store.put(entry)
                    lock.lock()
                    sizes[i] = size
                    previousSizes[i] = prevSize
                    lock.unlock()
                }
            }
            queue.waitUntilAllOperationsAreFinished()
            store.save()
        }

        // Phase 3 — assemble + filter + sort.
        var out: [InspectFinding] = []
        out.reserveCapacity(entries.count)
        for (i, e) in entries.enumerated() {
            guard let size = sizes[i], size >= minBytes else { continue }
            let f = InspectFinding(entry: e, sizeBytes: size, previousSizeBytes: previousSizes[i])
            out.append(f)
            onProgress?(f)
        }
        return out.sortedBySafetyThenSize()
    }

    /// Compare two optional dates at second granularity. The HFS / APFS
    /// timestamps we read back round to the second, so equality on `Date`
    /// instances misses by sub-second noise.
    private func sameSecond(_ a: Date?, _ b: Date?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case (let x?, let y?): return Int(x.timeIntervalSince1970) == Int(y.timeIntervalSince1970)
        default: return false
        }
    }
}
