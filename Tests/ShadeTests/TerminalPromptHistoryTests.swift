import AppKit
import SwiftTerm
import XCTest
@testable import Shade

final class TerminalPromptHistoryTests: XCTestCase {
    func testCommandCompletionCarriesExitCodeAndDuration() {
        let terminal = makeTerminal()
        var history = TerminalPromptHistory()
        let started = Date(timeIntervalSinceReferenceDate: 100)

        XCTAssertNil(history.record(
            payload: Array("C".utf8),
            row: 0,
            in: terminal,
            now: started
        ))

        let completion = history.record(
            payload: Array("D;17".utf8),
            row: 0,
            in: terminal,
            now: started.addingTimeInterval(2.5)
        )

        XCTAssertEqual(completion, .init(exitCode: 17, duration: 2.5))
        XCTAssertEqual(history.marks.count, 2)
    }

    func testCommandDoneWithoutStartHasNoDuration() {
        let terminal = makeTerminal()
        var history = TerminalPromptHistory()

        let completion = history.record(
            payload: Array("D;0".utf8),
            row: 0,
            in: terminal
        )

        XCTAssertEqual(completion, .init(exitCode: 0, duration: nil))
    }

    func testNewPromptAbandonsMissingCommandCompletion() {
        for prompt in ["A", "B"] {
            let terminal = makeTerminal()
            var history = TerminalPromptHistory()
            let started = Date(timeIntervalSinceReferenceDate: 100)
            _ = history.record(payload: Array("C".utf8), row: 0, in: terminal, now: started)
            XCTAssertTrue(history.isCommandRunning)

            _ = history.record(payload: Array(prompt.utf8), row: 1, in: terminal)
            XCTAssertFalse(history.isCommandRunning)
            let completion = history.record(
                payload: Array("D;0".utf8), row: 1, in: terminal,
                now: started.addingTimeInterval(30)
            )

            XCTAssertEqual(completion, .init(exitCode: 0, duration: nil))
        }
    }

    func testInvalidPayloadDoesNotMutateHistory() {
        let terminal = makeTerminal()
        var history = TerminalPromptHistory()

        XCTAssertNil(history.record(payload: Array("X".utf8), row: 0, in: terminal))
        XCTAssertTrue(history.marks.isEmpty)
    }

    func testLastCommandOutputReadsCompletedRange() {
        let terminal = makeTerminal()
        var history = TerminalPromptHistory()
        _ = history.record(payload: Array("C".utf8), row: 0, in: terminal)
        terminal.feed(text: "first\r\nsecond\r\n")
        _ = history.record(payload: Array("D;0".utf8), row: 2, in: terminal)

        XCTAssertEqual(history.lastCommandOutput(in: terminal), "first\nsecond")
    }

    func testLastCommandOutputRemovesVisualSoftWraps() {
        let terminal = makeTerminal(cols: 5)
        var history = TerminalPromptHistory()
        _ = history.record(payload: Array("C".utf8), row: 0, in: terminal)
        terminal.feed(text: "abcdefgh\r\n")
        _ = history.record(payload: Array("D;0".utf8), row: 2, in: terminal)

        XCTAssertEqual(history.lastCommandOutput(in: terminal), "abcdefgh")
    }

    func testNavigationAndCopyUseBufferRowsAfterScrollbackGrows() throws {
        let terminal = makeTerminal(cols: 20, rows: 4)
        var history = TerminalPromptHistory()
        _ = history.record(payload: Array("A".utf8), row: 0, in: terminal)
        _ = history.record(payload: Array("C".utf8), row: 0, in: terminal)
        for index in 1...8 {
            terminal.feed(text: "line-\(index)\r\n")
        }
        let doneRow = terminal.buffer.totalLinesTrimmed + terminal.buffer.yDisp
            + terminal.getCursorLocation().y
        _ = history.record(payload: Array("D;0".utf8), row: doneRow, in: terminal)
        _ = history.record(payload: Array("A".utf8), row: doneRow, in: terminal)

        XCTAssertGreaterThan(terminal.buffer.yDisp, 0)
        XCTAssertEqual(
            history.viewportRow(toward: .previous, in: terminal),
            0
        )
        XCTAssertEqual(
            try XCTUnwrap(history.lastCommandOutput(in: terminal)),
            (1...8).map { "line-\($0)" }.joined(separator: "\n")
        )
    }

    func testWidthReflowInvalidatesOutputAndNavigationCoordinates() {
        let terminal = makeTerminal(cols: 12)
        var history = TerminalPromptHistory()
        _ = history.record(payload: Array("A".utf8), row: 0, in: terminal)
        _ = history.record(payload: Array("C".utf8), row: 0, in: terminal)
        terminal.feed(text: "abcdefghijkl\r\n")
        _ = history.record(payload: Array("D;0".utf8), row: 1, in: terminal)
        XCTAssertEqual(history.lastCommandOutput(in: terminal), "abcdefghijkl")

        terminal.resize(cols: 6, rows: 24)

        XCTAssertNil(history.lastCommandOutput(in: terminal))
        XCTAssertNil(history.viewportRow(toward: .next, in: terminal))
        XCTAssertTrue(history.marks.isEmpty)
    }

    func testResizePreservesCommandTimingAndAcceptsNewOutputPairs() {
        let terminal = makeTerminal(cols: 12)
        var history = TerminalPromptHistory()
        let started = Date(timeIntervalSinceReferenceDate: 100)
        _ = history.record(payload: Array("C".utf8), row: 0, in: terminal, now: started)
        terminal.feed(text: "abcdefghijkl\r\n")
        terminal.resize(cols: 6, rows: 24)
        history.terminalResized(columns: terminal.cols)
        XCTAssertTrue(history.isCommandRunning)

        let completion = history.record(
            payload: Array("D;0".utf8), row: 2, in: terminal,
            now: started.addingTimeInterval(3)
        )

        XCTAssertEqual(completion, .init(exitCode: 0, duration: 3))
        XCTAssertFalse(history.isCommandRunning)
        XCTAssertNil(history.lastCommandOutput(in: terminal))
        terminal.feed(text: "\r\n")
        let row = terminal.getCursorLocation().y
        _ = history.record(payload: Array("C".utf8), row: row, in: terminal)
        terminal.feed(text: "new\r\n")
        _ = history.record(payload: Array("D;0".utf8), row: row + 1, in: terminal)
        XCTAssertEqual(history.lastCommandOutput(in: terminal), "new")
    }

    func testClearInvalidatesCoordinatesWithoutResettingCommandDuration() {
        let terminal = makeTerminal()
        var history = TerminalPromptHistory()
        let started = Date(timeIntervalSinceReferenceDate: 100)
        _ = history.record(payload: Array("C".utf8), row: 0, in: terminal, now: started)

        history.invalidateCoordinates()
        XCTAssertTrue(history.isCommandRunning)
        let completion = history.record(
            payload: Array("D;0".utf8), row: 1, in: terminal,
            now: started.addingTimeInterval(3)
        )

        XCTAssertEqual(completion, .init(exitCode: 0, duration: 3))
        XCTAssertNil(history.lastCommandOutput(in: terminal))
    }

    func testAlternateScreenCannotReadOrPruneNormalHistory() {
        let terminal = makeTerminal(cols: 20, rows: 4)
        var history = TerminalPromptHistory()
        terminal.feed(text: String(repeating: "older\r\n", count: 8))
        _ = history.record(payload: Array("A".utf8), row: 8, in: terminal)
        _ = history.record(payload: Array("C".utf8), row: 8, in: terminal)
        terminal.feed(text: "result\r\n")
        _ = history.record(payload: Array("D;0".utf8), row: 9, in: terminal)
        let normalMarks = history.marks

        terminal.feed(text: "\u{1B}[?1049hfull screen")

        XCTAssertTrue(terminal.isCurrentBufferAlternate)
        XCTAssertNil(history.lastCommandOutput(in: terminal))
        XCTAssertNil(history.viewportRow(toward: .previous, in: terminal))
        XCTAssertNil(history.viewportRow(toward: .next, in: terminal))
        XCTAssertNil(history.record(payload: Array("C".utf8), row: 0, in: terminal))
        XCTAssertEqual(history.marks, normalMarks)

        terminal.feed(text: "\u{1B}[?1049l")

        XCTAssertEqual(history.lastCommandOutput(in: terminal), "result")
        XCTAssertEqual(history.marks, normalMarks)
    }

    func testEmptyEnterKeepsOnlyLastCommandsOutput() {
        let terminal = makeTerminal()
        var history = TerminalPromptHistory()
        _ = history.record(payload: Array("C".utf8), row: 0, in: terminal)
        terminal.feed(text: "result\r\n")
        _ = history.record(payload: Array("D;0".utf8), row: 1, in: terminal)
        _ = history.record(payload: Array("A".utf8), row: 1, in: terminal)
        terminal.feed(text: "prompt> \r\n")
        _ = history.record(payload: Array("D;0".utf8), row: 2, in: terminal)
        _ = history.record(payload: Array("A".utf8), row: 2, in: terminal)

        XCTAssertEqual(history.lastCommandOutput(in: terminal), "result")
    }

    @MainActor
    func testProcessRecordsNormalMarksBeforeSameChunkSwitchesToAlternateScreen() throws {
        let process = TerminalProcessController()
        let view = try XCTUnwrap(process.view as? ActivityTerminalView)
        view.setFrameSize(NSSize(width: 640, height: 480))
        var history = TerminalPromptHistory()
        process.onPromptMark = { payload, row in
            _ = history.record(payload: payload, row: row, in: view.terminal)
        }
        let bytes = Array((
            "\u{1B}]133;C\u{07}result\r\n\u{1B}]133;D;0\u{07}"
                + "\u{1B}[?1049hfull screen"
        ).utf8)

        view.dataReceived(slice: bytes[...])

        XCTAssertTrue(view.terminal.isCurrentBufferAlternate)
        XCTAssertEqual(history.marks.map(\.kind), [.commandStart, .commandDone(exitCode: 0)])
        XCTAssertNil(history.lastCommandOutput(in: view.terminal))
        view.feed(text: "\u{1B}[?1049l")
        XCTAssertEqual(history.lastCommandOutput(in: view.terminal), "result")
    }

    @MainActor
    func testSessionInvalidatesMarksOnWidthRoundTripWithoutHistoryAccess() throws {
        let session = TerminalSession()
        let view = try XCTUnwrap(session.view as? ActivityTerminalView)
        view.setFrameSize(NSSize(width: 640, height: 480))
        let columns = view.terminal.cols
        let mark = Array("\u{1B}]133;A\u{07}".utf8)
        view.dataReceived(slice: mark[...])
        XCTAssertEqual(session.promptMarks.count, 1)

        // Resizing while a full-screen app is active reflows the normal buffer
        // too. No history read occurs between these two actual view resizes.
        view.feed(text: "\u{1B}[?1049h")
        view.setFrameSize(NSSize(width: 320, height: 480))
        view.setFrameSize(NSSize(width: 640, height: 480))
        view.feed(text: "\u{1B}[?1049l")

        XCTAssertEqual(view.terminal.cols, columns)
        XCTAssertTrue(session.promptMarks.isEmpty)
        view.dataReceived(slice: mark[...])
        XCTAssertEqual(session.promptMarks.count, 1)
    }

    private func makeTerminal(cols: Int = 80, rows: Int = 24) -> Terminal {
        Terminal(delegate: HistoryTerminalDelegate(), options: TerminalOptions(cols: cols, rows: rows))
    }
}

private final class HistoryTerminalDelegate: TerminalDelegate {
    func send(source: Terminal, data: ArraySlice<UInt8>) {}
}
