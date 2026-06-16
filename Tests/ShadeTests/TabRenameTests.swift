import XCTest
@testable import Shade

final class TabRenameTests: XCTestCase {
    // MARK: normalizedUserTitle

    func testNormalizedTrimsWhitespace() {
        XCTAssertEqual(TerminalSession.normalizedUserTitle("  logs  "), "logs")
    }

    func testNormalizedEmptyBecomesNil() {
        XCTAssertNil(TerminalSession.normalizedUserTitle(""))
        XCTAssertNil(TerminalSession.normalizedUserTitle("   \n\t "))
    }

    func testNormalizedKeepsInnerSpaces() {
        XCTAssertEqual(TerminalSession.normalizedUserTitle(" ssh prod "), "ssh prod")
    }

    // MARK: resolveDisplayTitle precedence

    func testUserTitleWinsOverEverything() {
        XCTAssertEqual(
            TerminalSession.resolveDisplayTitle(
                userTitle: "mine", remoteIndicator: "ssh",
                oscTitle: "osc", cwd: "~/x", shellName: "zsh"),
            "mine")
    }

    func testRemoteIndicatorWinsWhenNoUserTitle() {
        XCTAssertEqual(
            TerminalSession.resolveDisplayTitle(
                userTitle: nil, remoteIndicator: "ssh",
                oscTitle: "osc", cwd: "~/x", shellName: "zsh"),
            "[ssh]")
    }

    func testFallsBackOscThenCwdThenShell() {
        XCTAssertEqual(
            TerminalSession.resolveDisplayTitle(
                userTitle: nil, remoteIndicator: nil,
                oscTitle: "osc", cwd: "~/x", shellName: "zsh"),
            "osc")
        XCTAssertEqual(
            TerminalSession.resolveDisplayTitle(
                userTitle: nil, remoteIndicator: nil,
                oscTitle: "", cwd: "~/x", shellName: "zsh"),
            "~/x")
        XCTAssertEqual(
            TerminalSession.resolveDisplayTitle(
                userTitle: nil, remoteIndicator: nil,
                oscTitle: "", cwd: nil, shellName: "zsh"),
            "zsh")
    }

    func testEmptyUserTitleIsIgnored() {
        // normalizedUserTitle never yields "", but resolve stays defensive.
        XCTAssertEqual(
            TerminalSession.resolveDisplayTitle(
                userTitle: "", remoteIndicator: nil,
                oscTitle: "osc", cwd: nil, shellName: "zsh"),
            "osc")
    }
}
