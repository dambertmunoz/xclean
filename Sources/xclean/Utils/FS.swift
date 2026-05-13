import Foundation

enum FS {
    static let fm = FileManager.default

    static func exists(_ url: URL) -> Bool {
        return fm.fileExists(atPath: url.path)
    }

    static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        let ok = fm.fileExists(atPath: url.path, isDirectory: &isDir)
        return ok && isDir.boolValue
    }

    /// Recursive size of a file or directory, in bytes. Returns 0 on error.
    static func sizeOf(_ url: URL) -> UInt64 {
        guard exists(url) else { return 0 }

        if !isDirectory(url) {
            return (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(UInt64.init)) ?? 0
        }

        var total: UInt64 = 0
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey]
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles], errorHandler: { _, _ in true }) else {
            return 0
        }
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: Set(keys))
            if values?.isRegularFile == true {
                let size = values?.totalFileAllocatedSize
                    ?? values?.fileAllocatedSize
                    ?? 0
                total += UInt64(size)
            }
        }
        return total
    }

    /// Last modification date of a file or directory.
    static func lastModified(_ url: URL) -> Date? {
        return (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
    }

    /// Most recent mtime among the directory and its immediate children. Useful
    /// for catching "last used" on bundles whose root mtime never updates.
    static func mostRecentChildMTime(_ url: URL) -> Date? {
        var newest = lastModified(url)
        guard let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return newest
        }
        for child in contents {
            if let d = (try? child.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) {
                if newest == nil || d > newest! { newest = d }
            }
        }
        return newest
    }

    static func directChildren(_ url: URL) -> [URL] {
        guard let items = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }
        return items
    }
}
