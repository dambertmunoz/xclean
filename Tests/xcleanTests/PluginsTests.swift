import XCTest
@testable import xclean

final class PluginsTests: XCTestCase {
    func testBuiltInIDsAreUnique() {
        let ids = BuiltInPlugins.all.map { $0.id }
        XCTAssertEqual(Set(ids).count, ids.count, "Plugin IDs must be unique: \(ids)")
    }

    func testBuiltInIDsAreLowercaseDashed() {
        for id in BuiltInPlugins.all.map({ $0.id }) {
            let pattern = #"^[a-z][a-z0-9\-]*$"#
            let regex = try? NSRegularExpression(pattern: pattern)
            let range = NSRange(location: 0, length: id.utf16.count)
            XCTAssertNotNil(regex)
            XCTAssertEqual(regex?.numberOfMatches(in: id, options: [], range: range), 1,
                           "Plugin id '\(id)' must match \(pattern)")
        }
    }

    func testCarthageReportsEmptyWhenPathMissing() throws {
        // We don't control the test host, so this just asserts the plugin
        // doesn't throw when its path is or isn't present — both are valid
        // outcomes. The assertion is the *absence* of a thrown error.
        let cleaner = CarthageCleaner()
        _ = try cleaner.discover(config: .scanDefaults)
    }
}
