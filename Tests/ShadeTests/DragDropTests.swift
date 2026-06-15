import XCTest
@testable import Shade

final class DragDropTests: XCTestCase {
    func testShellQuotedWrapsPlainPath() {
        XCTAssertEqual(ActivityTerminalView.shellQuoted("/tmp/a"), "'/tmp/a'")
    }

    func testShellQuotedKeepsSpaces() {
        XCTAssertEqual(ActivityTerminalView.shellQuoted("/tmp/with space"), "'/tmp/with space'")
    }

    func testShellQuotedEscapesSingleQuote() {
        XCTAssertEqual(ActivityTerminalView.shellQuoted("/tmp/o'brien"), "'/tmp/o'\\''brien'")
    }
}
