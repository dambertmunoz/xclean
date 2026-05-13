import XCTest
@testable import xclean

final class ByteSizeTests: XCTestCase {
    func testBytes() {
        XCTAssertEqual(ByteSize.human(0), "0 B")
        XCTAssertEqual(ByteSize.human(512), "512 B")
        XCTAssertEqual(ByteSize.human(1023), "1023 B")
    }

    func testKilobytes() {
        XCTAssertEqual(ByteSize.human(1024), "1.00 KB")
        XCTAssertEqual(ByteSize.human(2048), "2.00 KB")
    }

    func testMegabytes() {
        XCTAssertEqual(ByteSize.human(1024 * 1024), "1.00 MB")
        XCTAssertEqual(ByteSize.human(1024 * 1024 * 3 + 512 * 1024), "3.50 MB")
    }

    func testGigabytes() {
        XCTAssertEqual(ByteSize.human(1024 * 1024 * 1024), "1.00 GB")
    }
}
