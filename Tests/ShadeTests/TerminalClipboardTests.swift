import AppKit
import SwiftTerm
import XCTest
@testable import Shade
@testable import ShadeCore

/// Clipboard actions use a private pasteboard so tests never touch the
/// user's real clipboard.
@MainActor
final class TerminalClipboardTests: XCTestCase {
    private var pasteboard: NSPasteboard!

    override func setUp() async throws {
        pasteboard = NSPasteboard(name: NSPasteboard.Name("shade-tests-\(UUID().uuidString)"))
    }

    override func tearDown() async throws {
        pasteboard.releaseGlobally()
    }

    func testCutCopiesTheSelectionAndClearsIt() {
        let controller = TerminalsController(preferences: StaticPreferences())
        let session = controller.newSession(configuration: .waitingForTermination)
        defer {
            session.onExit = nil
            session.terminate()
        }
        let keyboard = PanelKeyboardController(
            terminals: controller,
            preferences: isolatedPreferencesStore(),
            pasteboard: pasteboard
        )
        session.view.feed(text: "echo hello")
        session.view.extendShadeKeyboardSelection(direction: .left, byWord: true)
        XCTAssertEqual(session.view.getSelection(), "hello")

        keyboard.cutSelection()

        XCTAssertEqual(pasteboard.string(forType: .string), "hello")
        XCTAssertNil(session.view.getSelection())
    }

    func testPromptNavigationAndOutputCopyFollowOSC133Marks() throws {
        let session = TerminalSession(preferences: .defaults)
        let view = try XCTUnwrap(session.view as? ActivityTerminalView)
        view.setFrameSize(NSSize(width: 640, height: 240))
        var stream = "\u{1B}]133;A\u{07}$ \u{1B}]133;B\u{07}ls\r\n"
        stream += "\u{1B}]133;C\u{07}first output\r\nsecond output\r\n\u{1B}]133;D;0\u{07}"
        for line in 0..<80 { stream += "\u{1B}]133;A\u{07}$ \u{1B}]133;B\u{07}\u{1B}]133;C\u{07}row \(line)\r\n" }
        stream += "\u{1B}]133;A\u{07}$ "
        let bytes = Array(stream.utf8)

        view.dataReceived(slice: bytes[...])
        waitForCondition { session.promptMarks.filter { $0.kind == .promptStart }.count == 82 }

        XCTAssertTrue(session.copyLastCommandOutput(to: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), "first output\nsecond output")

        let liveRow = view.terminalStateSnapshot().viewportRow
        XCTAssertTrue(session.jumpToPreviousPrompt())
        let previousRow = view.terminalStateSnapshot().viewportRow
        XCTAssertLessThan(previousRow, liveRow)
        XCTAssertTrue(session.jumpToPreviousPrompt())
        XCTAssertLessThan(view.terminalStateSnapshot().viewportRow, previousRow)
        XCTAssertTrue(session.jumpToNextPrompt())
        XCTAssertEqual(view.terminalStateSnapshot().viewportRow, previousRow)
    }
}
