import AppKit
import SwiftTerm
import XCTest
@testable import Shade

@MainActor
final class TerminalSessionAppearanceTests: XCTestCase {
    func testReapplyingUnchangedPreferencesKeepsSelection() {
        let prefs = Preferences.defaults
        let session = selectedSession(prefs)

        session.apply(prefs)

        XCTAssertEqual(session.view.getSelection()?.contains("hello"), true)
    }

    func testUnrelatedPreferenceChangeKeepsSelection() {
        var prefs = Preferences.defaults
        let session = selectedSession(prefs)

        prefs.hideOnFocusLoss.toggle()
        prefs.widthFraction = 0.5
        session.apply(prefs)

        XCTAssertEqual(session.view.getSelection()?.contains("hello"), true)
    }

    func testChangedFontIsApplied() {
        var prefs = Preferences.defaults
        let session = TerminalSession(preferences: prefs)

        prefs.fontSize += 2
        session.apply(prefs)

        XCTAssertEqual(session.view.font.pointSize, prefs.fontSize)
    }

    func testChangedBackgroundOpacityIsApplied() {
        var prefs = Preferences.defaults
        prefs.backgroundOpacity = 0.9
        let session = TerminalSession(preferences: prefs)

        prefs.backgroundOpacity = 0.5
        session.apply(prefs)

        XCTAssertEqual(session.view.nativeBackgroundColor.alphaComponent, 0.5, accuracy: 0.001)
    }

    func testControllerCreatesSessionsFromInjectedPreferences() {
        var prefs = Preferences.defaults
        prefs.cursorShape = .bar
        prefs.cursorBlink = false
        prefs.fontSize = 17
        let controller = TerminalsController(preferences: StaticPreferences(preferences: prefs))

        let session = controller.newSession()
        defer { session.terminate() }

        XCTAssertEqual(session.view.terminalStateSnapshot().cursorStyle, .steadyBar)
        XCTAssertEqual(session.view.font.pointSize, 17)
    }

    private func selectedSession(_ prefs: Preferences) -> TerminalSession {
        let session = TerminalSession(preferences: prefs)
        session.view.feed(text: "hello")
        waitForCondition { session.view.terminalStateSnapshot().cursor.col == 5 }
        session.view.selectAll()
        XCTAssertEqual(session.view.getSelection()?.contains("hello"), true)
        return session
    }
}
