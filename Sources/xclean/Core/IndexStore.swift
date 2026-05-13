import Foundation

/// One row in the persistent index. Keyed by absolute path. We store the
/// `rootMtime` of the path at scan time so the next run can skip the walk
/// entirely when nothing changed.
///
/// `previousSizeBytes` carries the prior measurement so the UI can render
/// per-entry deltas without keeping a parallel data structure.
struct IndexEntry: Codable {
    let path: String
    let sizeBytes: UInt64
    let previousSizeBytes: UInt64?
    let rootMtime: Date?
    let computedAt: Date

    init(path: String,
         sizeBytes: UInt64,
         previousSizeBytes: UInt64? = nil,
         rootMtime: Date?,
         computedAt: Date) {
        self.path = path
        self.sizeBytes = sizeBytes
        self.previousSizeBytes = previousSizeBytes
        self.rootMtime = rootMtime
        self.computedAt = computedAt
    }
}

/// Persistent JSON cache living at:
/// `~/Library/Application Support/xclean/index.json`
///
/// Read once at startup, kept in memory as a dictionary, written atomically
/// when something changes. Footprint ≈ (entries * ~80 bytes), so a registry
/// with 80 entries fits in well under 10 KB on disk.
///
/// Concurrency: the in-memory store is protected by an `NSLock`. Readers and
/// writers are tiny, so contention is negligible compared to walking the FS.
final class IndexStore {
    private let url: URL
    private var entries: [String: IndexEntry] = [:]
    private let lock = NSLock()

    /// `~/Library/Application Support/xclean/`
    static var defaultDirectory: URL {
        let appSupport = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )) ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
        return appSupport.appendingPathComponent("xclean", isDirectory: true)
    }

    init(directory: URL = IndexStore.defaultDirectory) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.url = directory.appendingPathComponent("index.json")
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        guard let arr = try? JSONDecoder.iso.decode([IndexEntry].self, from: data) else { return }
        for e in arr { entries[e.path] = e }
    }

    func get(_ path: String) -> IndexEntry? {
        lock.lock(); defer { lock.unlock() }
        return entries[path]
    }

    func put(_ entry: IndexEntry) {
        lock.lock(); defer { lock.unlock() }
        entries[entry.path] = entry
    }

    func remove(path: String) {
        lock.lock(); defer { lock.unlock() }
        entries.removeValue(forKey: path)
    }

    /// Atomic write of the full table. Cheap — the dictionary is tiny.
    func save() {
        lock.lock()
        let snapshot = Array(entries.values)
        lock.unlock()
        guard let data = try? JSONEncoder.pretty.encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Snapshot of all rows, sorted by size descending.
    func allSortedBySize() -> [IndexEntry] {
        lock.lock(); defer { lock.unlock() }
        return entries.values.sorted { $0.sizeBytes > $1.sizeBytes }
    }
}

// `JSONDecoder.iso` / `JSONEncoder.iso` are declared in HistoryStore.swift.
// We use them directly here.

private extension JSONEncoder {
    static let pretty: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}
