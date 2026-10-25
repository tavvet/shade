import SwiftTerm
import XCTest
@testable import Shade

@MainActor
final class TerminalCursorStyleTests: XCTestCase {
    func testMapsEveryShapeAndBlinkCombination() {
        let expected: [(Preferences.CursorShape, Bool, CursorStyle)] = [
            (.block, true, .blinkBlock),
            (.block, false, .steadyBlock),
            (.underline, true, .blinkUnderline),
            (.underline, false, .steadyUnderline),
            (.bar, true, .blinkBar),
            (.bar, false, .steadyBar),
        ]
        for (shape, blink, style) in expected {
            XCTAssertEqual(TerminalAppearance.cursorStyle(for: prefs(shape, blink: blink)), style)
        }
    }

    func testTrackerSendsOnlyChangedPreferences() {
        let block = prefs(.block, blink: false)
        let bar = prefs(.bar, blink: false)
        var tracker = TerminalCursorStyleTracker(applied: .steadyBlock)

        XCTAssertNil(tracker.sequenceToApply(for: block))
        XCTAssertEqual(tracker.sequenceToApply(for: bar), "\u{1B}[6 q")
        XCTAssertNil(tracker.sequenceToApply(for: bar))
        XCTAssertEqual(tracker.applied, .steadyBar)
    }

    func testNewSessionStartsWithPreferredCursorStyle() {
        let session = TerminalSession(preferences: prefs(.bar, blink: true))

        XCTAssertEqual(session.view.terminalStateSnapshot().cursorStyle, .blinkBar)
    }

    func testReapplyingUnchangedPreferencesKeepsProgramCursorStyle() {
        let block = prefs(.block, blink: false)
        let session = TerminalSession(preferences: block)
        // A program such as vim switches to a bar cursor in insert mode.
        session.view.feed(text: "\u{1B}[6 q")
        waitForCursorStyle(.steadyBar, in: session)

        session.apply(block)
        flushParser(of: session)

        XCTAssertEqual(session.view.terminalStateSnapshot().cursorStyle, .steadyBar)
    }

    func testChangedPreferenceIsApplied() {
        let session = TerminalSession(preferences: prefs(.block, blink: false))

        session.apply(prefs(.underline, blink: true))

        waitForCursorStyle(.blinkUnderline, in: session)
    }

    func testDefaultCursorRequestRestoresPreference() {
        let session = TerminalSession(preferences: prefs(.bar, blink: false))
        session.view.feed(text: "\u{1B}[2 q")
        waitForCursorStyle(.steadyBlock, in: session)

        session.view.feed(text: "\u{1B}[0 q")

        waitForCursorStyle(.steadyBar, in: session)
    }

    private func prefs(_ shape: Preferences.CursorShape, blink: Bool) -> Preferences {
        var prefs = Preferences.defaults
        prefs.cursorShape = shape
        prefs.cursorBlink = blink
        return prefs
    }

    private func waitForCursorStyle(_ style: CursorStyle, in session: TerminalSession) {
        waitForCondition { session.view.terminalStateSnapshot().cursorStyle == style }
    }

    /// Feeds are parsed in order, so once this marker moves the cursor, every
    /// earlier local feed has been processed too.
    private func flushParser(of session: TerminalSession) {
        let column = session.view.terminalStateSnapshot().cursor.col
        session.view.feed(text: "x")
        waitForCondition { session.view.terminalStateSnapshot().cursor.col != column }
    }
}
