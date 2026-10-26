import AppKit
import SwiftTerm
import XCTest
@testable import Shade
@testable import ShadeCore

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

    func testConfiguredLinkHighlightColorIsAppliedToTheView() throws {
        var prefs = Preferences.defaults
        let session = TerminalSession(preferences: prefs)
        let initial = try XCTUnwrap(session.view.linkHighlightColor?.usingColorSpace(.sRGB))
        XCTAssertEqual(initial.redComponent, 1, accuracy: 0.01)
        XCTAssertEqual(initial.greenComponent, 0.8, accuracy: 0.01)

        prefs.linkHighlightHex = "00CCFF"
        session.apply(prefs)

        let updated = try XCTUnwrap(session.view.linkHighlightColor?.usingColorSpace(.sRGB))
        XCTAssertEqual(updated.redComponent, 0, accuracy: 0.01)
        XCTAssertEqual(updated.greenComponent, 0.8, accuracy: 0.01)
        XCTAssertEqual(updated.blueComponent, 1, accuracy: 0.01)
    }

    func testChangedBackgroundOpacityIsApplied() {
        var prefs = Preferences.defaults
        prefs.backgroundOpacity = 0.9
        let session = TerminalSession(preferences: prefs)

        prefs.backgroundOpacity = 0.5
        session.apply(prefs)

        XCTAssertEqual(session.view.nativeBackgroundColor.alphaComponent, 0.5, accuracy: 0.001)
    }

    func testChangedBackgroundColorIsAppliedWithTheOpacity() throws {
        var prefs = Preferences.defaults
        prefs.backgroundOpacity = 0.8
        let session = TerminalSession(preferences: prefs)

        prefs.backgroundHex = "336699"
        session.apply(prefs)

        let color = try XCTUnwrap(session.view.nativeBackgroundColor.usingColorSpace(.sRGB))
        XCTAssertEqual(Preferences.hex(for: color), "336699")
        XCTAssertEqual(color.alphaComponent, 0.8, accuracy: 0.001)

        prefs.backgroundOpacity = 0.5
        session.apply(prefs)

        let faded = try XCTUnwrap(session.view.nativeBackgroundColor.usingColorSpace(.sRGB))
        XCTAssertEqual(Preferences.hex(for: faded), "336699")
        XCTAssertEqual(faded.alphaComponent, 0.5, accuracy: 0.001)
    }

    func testTextColorIsAppliedAtStartAndWhenChanged() throws {
        var prefs = Preferences.defaults
        prefs.foregroundHex = "C0FFEE"
        let session = TerminalSession(preferences: prefs)
        let initial = try XCTUnwrap(session.view.nativeForegroundColor.usingColorSpace(.sRGB))
        XCTAssertEqual(Preferences.hex(for: initial), "C0FFEE")

        prefs.foregroundHex = "336699"
        session.apply(prefs)

        let updated = try XCTUnwrap(session.view.nativeForegroundColor.usingColorSpace(.sRGB))
        XCTAssertEqual(Preferences.hex(for: updated), "336699")
    }

    func testVisualBellFlashesInTheTextColor() throws {
        var prefs = Preferences.defaults
        prefs.foregroundHex = "102030"
        let session = TerminalSession(preferences: prefs)

        TerminalAppearance.flashBell(in: session.view)

        let flash = try XCTUnwrap(session.view.subviews.last?.layer?.backgroundColor)
        let color = try XCTUnwrap(NSColor(cgColor: flash)?.usingColorSpace(.sRGB))
        XCTAssertEqual(Preferences.hex(for: color), "102030")
        XCTAssertEqual(color.alphaComponent, 0.22, accuracy: 0.001)
    }

    func testControllerCreatesSessionsFromInjectedPreferences() {
        var prefs = Preferences.defaults
        prefs.cursorShape = .bar
        prefs.cursorBlink = false
        prefs.fontSize = 17
        let controller = TerminalsController(preferences: StaticPreferences(preferences: prefs))

        let session = controller.newSession(configuration: .waitingForTermination)
        defer {
            session.onExit = nil
            session.terminate()
        }

        XCTAssertEqual(session.view.terminalStateSnapshot().cursorStyle, .steadyBar)
        XCTAssertEqual(session.view.font.pointSize, 17)
    }

    func testControllerAnswersVisualBellFromLivePreferences() {
        let preferences = MutablePreferences()
        let controller = TerminalsController(preferences: preferences)
        let session = controller.newSession(configuration: .waitingForTermination)
        defer {
            session.onExit = nil
            session.terminate()
        }

        XCTAssertEqual(session.shouldFlashBell?(), false)
        preferences.preferences.visualBell = true
        XCTAssertEqual(session.shouldFlashBell?(), true)
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
