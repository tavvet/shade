import AppKit
import XCTest
@testable import Shade

@MainActor
final class PanelKeyboardZoomTests: XCTestCase {
    func testRapidZoomKeysAreSavedInOrder() async throws {
        let store = isolatedPreferencesStore()
        let keyboard = PanelKeyboardController(
            terminals: TerminalsController(preferences: StaticPreferences()),
            preferences: store
        )
        let start = store.load().fontSize

        for (keyCode, character) in [
            (KeyCodes.equal, "="), (KeyCodes.equal, "="), (KeyCodes.minus, "-"),
        ] {
            XCTAssertTrue(keyboard.panelHandleKey(try commandKey(keyCode, character)))
        }
        await keyboard.waitForPendingSave()

        XCTAssertEqual(store.load().fontSize, start + 1)
    }

    func testResetZoomRestoresTheDefaultSize() async throws {
        let store = isolatedPreferencesStore()
        store.saveFontSize(20)
        let keyboard = PanelKeyboardController(
            terminals: TerminalsController(preferences: StaticPreferences()),
            preferences: store
        )

        XCTAssertTrue(keyboard.panelHandleKey(try commandKey(KeyCodes.zero, "0")))
        await keyboard.waitForPendingSave()

        XCTAssertEqual(store.load().fontSize, Preferences.defaults.fontSize)
    }

    private func commandKey(_ keyCode: UInt16, _ character: String) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0,
            windowNumber: 0, context: nil, characters: character,
            charactersIgnoringModifiers: character, isARepeat: false, keyCode: keyCode
        ))
    }
}
