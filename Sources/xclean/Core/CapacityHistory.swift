import Foundation

/// Time-series of free disk space. Sampled at most once per hour, capped at
/// `maxSamples` (default: 168 = one week at hourly granularity).
///
/// Footprint: ~16 bytes / sample (Date + UInt64) → ~2.7 KB for a full week on
/// disk in JSON. Memory cost is identical.
final class CapacityHistory {

    struct Sample: Codable, Equatable {
        let timestamp: Date
        let availableBytes: UInt64
    }

    private let url: URL
    private let lock = NSLock()
    private var samples: [Sample] = []
    let maxSamples: Int
    /// Minimum gap between accepted samples. Keeps the series at hourly
    /// resolution regardless of how often `recordIfDue` is called.
    private let minInterval: TimeInterval

    init(directory: URL = IndexStore.defaultDirectory,
         maxSamples: Int = 168,
         minInterval: TimeInterval = 3600) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.url = directory.appendingPathComponent("capacity-history.json")
        self.maxSamples = maxSamples
        self.minInterval = minInterval
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        if let parsed = try? JSONDecoder.iso.decode([Sample].self, from: data) {
            samples = parsed
        }
    }

    private func save() {
        if let data = try? JSONEncoder.iso.encode(samples) {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - recording

    /// Records a new sample, but only if `minInterval` has passed since the
    /// last one. Returns `true` if it was actually persisted.
    @discardableResult
    func recordIfDue(availableBytes: UInt64, at date: Date = Date()) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if let last = samples.last, date.timeIntervalSince(last.timestamp) < minInterval {
            return false
        }
        samples.append(Sample(timestamp: date, availableBytes: availableBytes))
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }
        save()
        return true
    }

    func all() -> [Sample] {
        lock.lock(); defer { lock.unlock() }
        return samples
    }

    // MARK: - sparkline rendering

    /// Renders the series as a Unicode block-sparkline of `width` glyphs.
    /// If we don't have enough samples, the output is padded on the left.
    func sparkline(width: Int = 12) -> String {
        let bars: [Character] = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
        lock.lock()
        let series = samples
        lock.unlock()
        guard !series.isEmpty else { return String(repeating: "·", count: width) }

        // Bucket the series into `width` evenly-spaced buckets. For each
        // bucket we take the *average* — smooths short spikes.
        let buckets = bucketize(series: series.map { $0.availableBytes }, into: width)

        guard let minV = buckets.min(), let maxV = buckets.max(), maxV > minV else {
            return String(repeating: bars[bars.count / 2], count: width)
        }
        let span = Double(maxV - minV)
        return String(buckets.map { value -> Character in
            let normalized = Double(value - minV) / span
            let idx = min(bars.count - 1, max(0, Int(normalized * Double(bars.count - 1))))
            return bars[idx]
        })
    }

    /// Average of each non-overlapping chunk so a long series compresses
    /// nicely into a short sparkline.
    private func bucketize(series: [UInt64], into width: Int) -> [UInt64] {
        guard width > 0 else { return [] }
        if series.count <= width {
            // Left-pad with the earliest known value so the line starts on
            // a real data point.
            let pad = width - series.count
            return Array(repeating: series.first ?? 0, count: pad) + series
        }
        let chunkSize = Double(series.count) / Double(width)
        var out: [UInt64] = []
        out.reserveCapacity(width)
        var idx = 0.0
        for _ in 0..<width {
            let start = Int(idx.rounded(.down))
            let end = min(series.count, Int((idx + chunkSize).rounded(.down)))
            let slice = series[start..<max(start + 1, end)]
            let sum = slice.reduce(UInt64(0), +)
            out.append(sum / UInt64(slice.count))
            idx += chunkSize
        }
        return out
    }

    // MARK: - delta queries

    /// Free space `seconds` ago, or `nil` if no sample is old enough.
    func availableBytes(secondsAgo seconds: TimeInterval, at now: Date = Date()) -> UInt64? {
        lock.lock(); defer { lock.unlock() }
        let target = now.addingTimeInterval(-seconds)
        // Pick the newest sample <= target.
        var best: Sample?
        for s in samples where s.timestamp <= target {
            if best == nil || s.timestamp > best!.timestamp { best = s }
        }
        return best?.availableBytes
    }

    // MARK: - projection

    /// Slope of the linear regression over the samples, in bytes/second.
    /// Negative means free space is shrinking. `nil` if fewer than 3 samples
    /// or no variance in time.
    func slopeBytesPerSecond() -> Double? {
        lock.lock(); let series = samples; lock.unlock()
        guard series.count >= 3 else { return nil }
        let base = series.first!.timestamp.timeIntervalSinceReferenceDate
        let xs = series.map { $0.timestamp.timeIntervalSinceReferenceDate - base }
        let ys = series.map { Double($0.availableBytes) }
        let n = Double(series.count)
        let xMean = xs.reduce(0, +) / n
        let yMean = ys.reduce(0, +) / n
        var num = 0.0
        var den = 0.0
        for i in 0..<series.count {
            let dx = xs[i] - xMean
            num += dx * (ys[i] - yMean)
            den += dx * dx
        }
        guard den > 0 else { return nil }
        return num / den
    }

    /// Estimated seconds until free disk hits zero at the current rate.
    /// `nil` when disk is growing (slope ≥ 0) or there's not enough data.
    func projectedExhaustionSeconds(currentAvailable: UInt64) -> TimeInterval? {
        guard let slope = slopeBytesPerSecond(), slope < 0 else { return nil }
        let secondsLeft = -Double(currentAvailable) / slope
        // Anything more than 365 days out we treat as "not soon enough to
        // matter" — both for noise and to avoid silly "in 4 years" headers.
        guard secondsLeft.isFinite, secondsLeft > 0, secondsLeft < 365 * 86_400 else { return nil }
        return secondsLeft
    }
}
