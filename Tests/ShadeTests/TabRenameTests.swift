import XCTest
@testable import Shade

final class TabRenameTests: XCTestCase {
    // MARK: normalizedUserTitle

    func testNormalizedTrimsWhitespace() {
        XCTAssertEqual(TerminalPresentationState.normalizedUserTitle("  logs  "), "logs")
    }

    func testNormalizedEmptyBecomesNil() {
        XCTAssertNil(TerminalPresentationState.normalizedUserTitle(""))
        XCTAssertNil(TerminalPresentationState.normalizedUserTitle("   \n\t "))
    }

    func testNormalizedKeepsInnerSpaces() {
        XCTAssertEqual(TerminalPresentationState.normalizedUserTitle(" ssh prod "), "ssh prod")
    }

    // MARK: resolveDisplayTitle precedence

    func testUserTitleWinsOverEverything() {
        XCTAssertEqual(
            TerminalPresentationState.resolveDisplayTitle(
                userTitle: "mine", remoteIndicator: "ssh",
                oscTitle: "osc", cwd: "~/x", shellName: "zsh"),
            "mine")
    }

    func testRemoteIndicatorWinsWhenNoUserTitle() {
        XCTAssertEqual(
            TerminalPresentationState.resolveDisplayTitle(
                userTitle: nil, remoteIndicator: "ssh",
                oscTitle: "osc", cwd: "~/x", shellName: "zsh"),
            "[ssh]")
    }

    func testFallsBackOscThenCwdThenShell() {
        XCTAssertEqual(
            TerminalPresentationState.resolveDisplayTitle(
                userTitle: nil, remoteIndicator: nil,
                oscTitle: "osc", cwd: "~/x", shellName: "zsh"),
            "osc")
        XCTAssertEqual(
            TerminalPresentationState.resolveDisplayTitle(
                userTitle: nil, remoteIndicator: nil,
                oscTitle: "", cwd: "~/x", shellName: "zsh"),
            "~/x")
        XCTAssertEqual(
            TerminalPresentationState.resolveDisplayTitle(
                userTitle: nil, remoteIndicator: nil,
                oscTitle: "", cwd: nil, shellName: "zsh"),
            "zsh")
    }

    func testEmptyUserTitleIsIgnored() {
        // normalizedUserTitle never yields "", but resolve stays defensive.
        XCTAssertEqual(
            TerminalPresentationState.resolveDisplayTitle(
                userTitle: "", remoteIndicator: nil,
                oscTitle: "osc", cwd: nil, shellName: "zsh"),
            "osc")
    }

    func testPresentationNormalizesRenameAndNotifiesOnlyOnChange() {
        let state = TerminalPresentationState(shellName: "zsh")
        var changes = 0
        state.onChange = { changes += 1 }

        state.setUserTitle("  logs  ")
        state.setUserTitle("logs")

        XCTAssertEqual(state.userTitle, "logs")
        XCTAssertEqual(changes, 1)
    }

    func testBackgroundActivityCoalescesAndClearsOnActivation() {
        let state = TerminalPresentationState(shellName: "zsh")
        var changes = 0
        state.onChange = { changes += 1 }

        state.noteActivity()
        state.noteActivity()
        XCTAssertTrue(state.hasUnseenActivity)
        XCTAssertEqual(changes, 1)

        state.setActive(true)
        XCTAssertFalse(state.hasUnseenActivity)
        XCTAssertEqual(changes, 2)

        state.noteActivity()
        XCTAssertFalse(state.hasUnseenActivity)
        XCTAssertEqual(changes, 2)
    }

    func testDisplayTitleUsesOwnedStateAndExternalContext() {
        let state = TerminalPresentationState(shellName: "zsh")
        state.setOscTitle("osc")
        XCTAssertEqual(state.displayTitle(remoteIndicator: nil, cwd: "/tmp"), "osc")

        state.setUserTitle("prod")
        XCTAssertEqual(state.displayTitle(remoteIndicator: "ssh", cwd: "/tmp"), "prod")
    }
}
