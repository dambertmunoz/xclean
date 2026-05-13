import Foundation

/// One audit-trail entry — a destructive action that ran (or was attempted).
struct HistoryEvent: Codable, Equatable {
    enum Kind: String, Codable {
        case cleanup       // ran a shell command
        case trash         // moved to Trash
        case bulk          // bulk reclaim step
    }

    let timestamp: Date
    let kind: Kind
    let label: String              // human-readable, e.g. "uv cache clean"
    let pathString: String?        // path acted upon, if any
    let bytesFreed: UInt64         // measured delta after refresh (0 if unknown)
    let success: Bool
    let failureMessage: String?    // present if !success
}

/// Append-only log of operations. Stored at
/// `~/Library/Application Support/xclean/history.json` and capped at
/// `maxEntries` (rotating — oldest dropped first).
///
/// Footprint: ~80 bytes per entry. 500 entries ≈ 40 KB on disk.
/// Thread-safe via an internal `NSLock`.
final class HistoryStore {
    private let url: URL
    private let lock = NSLock()
    private var events: [HistoryEvent] = []
    /// Hard cap so the JSON never balloons. Old events drop off the front.
    let maxEntries: Int

    init(directory: URL = IndexStore.defaultDirectory, maxEntries: Int = 500) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.url = directory.appendingPathComponent("history.json")
        self.maxEntries = maxEntries
        load()
    }

    // MARK: - persistence

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        if let parsed = try? JSONDecoder.iso.decode([HistoryEvent].self, from: data) {
            events = parsed
        }
    }

    /// Write atomically. Cheap — entries are tiny and capped.
    private func save() {
        let snapshot: [HistoryEvent]
        // Take the snapshot under the lock so the encode/write is consistent.
        // We're already inside the lock when `save()` is called.
        snapshot = events
        if let data = try? JSONEncoder.iso.encode(snapshot) {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - mutation

    func append(_ event: HistoryEvent) {
        lock.lock(); defer { lock.unlock() }
        events.append(event)
        if events.count > maxEntries {
            events.removeFirst(events.count - maxEntries)
        }
        save()
    }

    // MARK: - queries

    /// Newest first.
    func recent(limit: Int) -> [HistoryEvent] {
        lock.lock(); defer { lock.unlock() }
        return Array(events.suffix(limit).reversed())
    }

    /// Total bytes freed by successful events whose timestamp falls inside the
    /// given window. Zero-failure-safe.
    func bytesFreed(since: Date) -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        return events.reduce(into: UInt64(0)) { acc, e in
            if e.success && e.timestamp >= since {
                acc &+= e.bytesFreed
            }
        }
    }

    /// Bytes freed since `since` of midnight today (local time).
    func bytesFreedToday() -> UInt64 {
        let start = Calendar.current.startOfDay(for: Date())
        return bytesFreed(since: start)
    }
}

// MARK: - JSONEncoder/Decoder ISO date helpers

extension JSONDecoder {
    static let iso: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

extension JSONEncoder {
    static let iso: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()
}
