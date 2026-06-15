import XCTest
@testable import Shade

final class CommandNotifierTests: XCTestCase {
    func testHumanDurationSeconds() {
        XCTAssertEqual(CommandNotifier.humanDuration(0), "0s")
        XCTAssertEqual(CommandNotifier.humanDuration(5), "5s")
        XCTAssertEqual(CommandNotifier.humanDuration(59), "59s")
    }

    func testHumanDurationMinutes() {
        XCTAssertEqual(CommandNotifier.humanDuration(60), "1m")
        XCTAssertEqual(CommandNotifier.humanDuration(65), "1m 5s")
        XCTAssertEqual(CommandNotifier.humanDuration(125), "2m 5s")
    }

    func testHumanDurationHours() {
        XCTAssertEqual(CommandNotifier.humanDuration(3600), "1h")
        XCTAssertEqual(CommandNotifier.humanDuration(3725), "1h 2m")
    }

    func testAbbreviateHome() {
        XCTAssertEqual(CommandNotifier.abbreviateHome(""), "")
        XCTAssertEqual(CommandNotifier.abbreviateHome("/tmp/x"), "/tmp/x")
        XCTAssertEqual(CommandNotifier.abbreviateHome(NSHomeDirectory()), "~")
        XCTAssertEqual(CommandNotifier.abbreviateHome(NSHomeDirectory() + "/projects"), "~/projects")
    }
}
