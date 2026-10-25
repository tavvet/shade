import AppKit
import SwiftTerm
import XCTest
@testable import Shade

@MainActor
final class TerminalScreenClearTests: XCTestCase {
    func testCommandKDoesNotSubmitPendingPTYInput() throws {
        let controller = TerminalsController(preferences: StaticPreferences())
        let session = controller.newSession(configuration: TerminalLaunchConfiguration(
            initialCommand: ProcessInvocation(executable: "/bin/sh", arguments: [
                "-c", "IFS= read -r line; printf 'SUBMITTED_%s\\n' \"$line\"; /bin/sleep 5"
            ])
        ))
        defer {
            session.onExit = nil
            session.terminate()
        }
        let keyboard = PanelKeyboardController(terminals: controller, preferences: isolatedPreferencesStore())
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        session.sendUserInput(Array("probe".utf8))
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0,
            windowNumber: 0, context: nil, characters: "k", charactersIgnoringModifiers: "k",
            isARepeat: false, keyCode: KeyCodes.asciiLetterForKeyCode.first { $0.value == "k" }!.key
        ))

        XCTAssertTrue(keyboard.panelHandleKey(event))
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        XCTAssertFalse(contents(of: session.view).contains("SUBMITTED_probe"))

        // Check that the pending line still executes normally on an explicit Enter.
        session.sendUserInput([0x0D])
        let deadline = Date().addingTimeInterval(2)
        while !contents(of: session.view).contains("SUBMITTED_probe"), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(contents(of: session.view).contains("SUBMITTED_probe"))
    }

    private func contents(of view: TerminalView) -> String {
        String(decoding: view.getBufferAsData(), as: UTF8.self)
    }
}
