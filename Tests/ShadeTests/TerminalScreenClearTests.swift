import AppKit
import SwiftTerm
import XCTest
@testable import Shade

@MainActor
final class TerminalScreenClearTests: XCTestCase {
    func testClearPreservesInputAndCursorWithoutSendingBytes() {
        let transport = RecordingClearTransport()
        let terminal = Terminal(delegate: transport, options: TerminalOptions(cols: 40, rows: 5))
        terminal.feed(text: "old output\r\n\r\n$ echo pending")
        terminal.feed(text: "\u{1B}[3D")
        let cursor = terminal.getCursorLocation()

        XCTAssertTrue(TerminalScreenClear.clearPreviousOutput(in: terminal))

        XCTAssertEqual(terminal.bufferLine(atRow: 0)?.translateToString(trimRight: true), "")
        XCTAssertEqual(terminal.bufferLine(atRow: 2)?.translateToString(trimRight: true), "$ echo pending")
        XCTAssertEqual(terminal.getCursorLocation().x, cursor.x)
        XCTAssertEqual(terminal.getCursorLocation().y, cursor.y)
        XCTAssertTrue(transport.sent.isEmpty)
    }

    func testClearPreservesEntireSoftWrappedInputIncludingPendingWrap() {
        let terminal = Terminal(delegate: RecordingClearTransport(), options: TerminalOptions(cols: 6, rows: 5))
        terminal.feed(text: "old\r\n$ abcdefghij")
        let original = terminal.getText(start: Position(col: 0, row: 1), end: Position(col: 6, row: 2))
        let cursor = terminal.getCursorLocation()

        XCTAssertTrue(TerminalScreenClear.clearPreviousOutput(in: terminal))

        XCTAssertEqual(terminal.getText(start: Position(col: 0, row: 1), end: Position(col: 6, row: 2)), original)
        XCTAssertEqual(terminal.getCursorLocation().x, cursor.x)
        XCTAssertEqual(terminal.getCursorLocation().y, cursor.y)
        XCTAssertEqual(terminal.bufferLine(atRow: 2)?.isWrapped, true)
    }

    func testClearDoesNotInterruptPartiallyReceivedEscapeSequence() {
        let transport = RecordingClearTransport()
        let terminal = Terminal(delegate: transport, options: TerminalOptions(cols: 40, rows: 5))
        terminal.feed(text: "old output\r\n$ pending\u{1B}[")
        let cursor = terminal.getCursorLocation()

        XCTAssertTrue(TerminalScreenClear.clearPreviousOutput(in: terminal))
        terminal.feed(text: "3D")

        XCTAssertEqual(terminal.getCursorLocation().x, cursor.x - 3)
        XCTAssertEqual(terminal.getCursorLocation().y, cursor.y)
        XCTAssertEqual(terminal.bufferLine(atRow: 1)?.translateToString(trimRight: true), "$ pending")
        XCTAssertTrue(transport.sent.isEmpty)
    }

    func testClearPreservesHardLineBreaksInsideSemanticPrompt() {
        let terminal = Terminal(delegate: RecordingClearTransport(), options: TerminalOptions(cols: 40, rows: 5))
        terminal.feed(text: "old output\r\n\u{1B}]133;A\u{7}directory\r\n$ \u{1B}]133;B\u{7}echo pending")

        XCTAssertTrue(TerminalScreenClear.clearPreviousOutput(in: terminal))

        XCTAssertEqual(terminal.bufferLine(atRow: 0)?.translateToString(trimRight: true), "")
        XCTAssertEqual(terminal.bufferLine(atRow: 1)?.translateToString(trimRight: true), "directory")
        XCTAssertEqual(terminal.bufferLine(atRow: 2)?.translateToString(trimRight: true), "$ echo pending")
    }

    func testClearDoesNotAlterAlternateScreen() {
        let terminal = Terminal(delegate: RecordingClearTransport(), options: TerminalOptions(cols: 20, rows: 4))
        terminal.feed(text: "\u{1B}[?1049hfirst\r\nsecond")
        let original = contents(of: terminal)

        XCTAssertFalse(TerminalScreenClear.clearPreviousOutput(in: terminal))
        XCTAssertEqual(contents(of: terminal), original)
    }

    func testRunningCommandDoesNotPreserveAnOldPromptAndAllItsOutput() {
        let terminal = Terminal(delegate: RecordingClearTransport(), options: TerminalOptions(cols: 40, rows: 5))
        terminal.feed(text: "\u{1B}]133;A\u{7}$ \u{1B}]133;B\u{7}long-command\r\n\u{1B}]133;C\u{7}old output\r\nlatest output")

        XCTAssertTrue(TerminalScreenClear.clearPreviousOutput(in: terminal, preservePrompt: false))

        XCTAssertEqual(terminal.bufferLine(atRow: 0)?.translateToString(trimRight: true), "")
        XCTAssertEqual(terminal.bufferLine(atRow: 1)?.translateToString(trimRight: true), "")
        XCTAssertEqual(terminal.bufferLine(atRow: 2)?.translateToString(trimRight: true), "latest output")
        XCTAssertTrue(terminal.semanticPromptMarks(at: 0).isEmpty)
    }

    func testCommandKDoesNotSubmitPendingPTYInput() throws {
        let controller = TerminalsController()
        let session = controller.newSession(configuration: TerminalLaunchConfiguration(
            initialCommand: ProcessInvocation(executable: "/bin/sh", arguments: [
                "-c", "IFS= read -r line; printf 'SUBMITTED_%s\\n' \"$line\"; /bin/sleep 5"
            ])
        ))
        defer {
            session.onExit = nil
            session.terminate()
        }
        let keyboard = PanelKeyboardController(terminals: controller)
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
        XCTAssertFalse(contents(of: session.view.getTerminal()).contains("SUBMITTED_probe"))

        // Check that the pending line still executes normally on an explicit Enter.
        session.sendUserInput([0x0D])
        let deadline = Date().addingTimeInterval(2)
        while !contents(of: session.view.getTerminal()).contains("SUBMITTED_probe"), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(contents(of: session.view.getTerminal()).contains("SUBMITTED_probe"))
    }

    private func contents(of terminal: Terminal) -> String {
        guard let lastRow = TerminalBufferGeometry.lastBufferRow(in: terminal) else { return "" }
        return (0...lastRow).compactMap {
            terminal.bufferLine(atRow: $0)?.translateToString(trimRight: true)
        }.joined(separator: "\n")
    }
}

private final class RecordingClearTransport: TerminalDelegate {
    var sent: [UInt8] = []

    func send(source: Terminal, data: ArraySlice<UInt8>) {
        sent.append(contentsOf: data)
    }
}
