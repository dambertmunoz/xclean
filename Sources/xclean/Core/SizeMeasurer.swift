import Foundation

/// Fast on-disk size measurement.
///
/// Shells out to `/usr/bin/du -sk` because Apple's `du` uses optimized syscalls
/// (`getattrlistbulk`, `fts_*`) and a tight C loop that walks gigabytes-of-files
/// in seconds with near-zero Swift allocation. We never accumulate the file
/// list in memory — only `du`'s small RSS plus a single integer result.
///
/// `FS.sizeOf` remains as a fallback for the rare cases where `du` fails.
enum SizeMeasurer {
    /// Computes the recursive size of `url` in bytes.
    /// Returns 0 if the path does not exist.
    static func size(of url: URL) -> UInt64 {
        guard FS.exists(url) else { return 0 }

        // Apple's du prints "<KB-blocks>\t<path>\n". -sk forces 1KB blocks and
        // a single summary line per argument.
        let r = Shell.run("/usr/bin/du", ["-sk", url.path])
        if r.success {
            let firstLine = r.stdout.split(separator: "\n", omittingEmptySubsequences: true).first ?? ""
            let firstToken = firstLine.split(separator: "\t", omittingEmptySubsequences: true).first
                ?? firstLine.split(separator: " ", omittingEmptySubsequences: true).first
            if let token = firstToken,
               let kb = UInt64(token.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return kb &* 1024
            }
        }
        // Fallback: Foundation enumerator. Slower but always works.
        return FS.sizeOf(url)
    }

    /// Single-stat mtime of a path. No recursion.
    static func mtime(of url: URL) -> Date? {
        return FS.lastModified(url)
    }
}
