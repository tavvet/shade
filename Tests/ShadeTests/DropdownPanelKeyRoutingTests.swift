import AppKit
import XCTest
@testable import Shade

@MainActor
final class DropdownPanelKeyRoutingTests: XCTestCase {
    func testSendEventFallsBackToPanelShortcutForModifiedNavigationKey() throws {
        let panel = DropdownPanel()
        let handler = RecordingPanelKeyHandler()
        panel.keyHandler = handler
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .shift, .function, .numericPad],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{F700}",
            charactersIgnoringModifiers: "\u{F700}",
            isARepeat: false,
            keyCode: KeyCodes.upArrow
        ))

        panel.sendEvent(event)

        XCTAssertEqual(handler.shortcuts, [.previousPrompt])
        XCTAssertEqual(handler.userInputCount, 1)
        XCTAssertTrue(handler.terminalInputs.isEmpty)
    }

    func testPerformKeyEquivalentRecordsHandledShortcutAsUserInput() throws {
        let panel = DropdownPanel()
        let handler = RecordingPanelKeyHandler()
        panel.keyHandler = handler
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "O",
            charactersIgnoringModifiers: "o",
            isARepeat: false,
            keyCode: KeyCodes.asciiLetterForKeyCode.first { $0.value == "o" }!.key
        ))

        XCTAssertTrue(panel.performKeyEquivalent(with: event))
        XCTAssertEqual(handler.shortcuts, [.copyLastCommandOutput])
        XCTAssertEqual(handler.userInputCount, 1)
    }
}

@MainActor
private final class RecordingPanelKeyHandler: PanelKeyHandler {
    private(set) var userInputCount = 0
    private(set) var shortcuts: [PanelShortcut] = []
    private(set) var terminalInputs: [PanelTerminalInput] = []

    func panelDidReceiveUserInput() {
        userInputCount += 1
    }

    func panelHandleKey(_ event: NSEvent) -> Bool {
        guard let shortcut = PanelShortcutResolver.resolve(
            keyCode: event.keyCode,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
            modifierFlags: event.modifierFlags,
            tabCount: 1
        ) else { return false }
        shortcuts.append(shortcut)
        return true
    }

    func panelHandleTerminalInput(_ input: PanelTerminalInput) {
        terminalInputs.append(input)
    }
}
