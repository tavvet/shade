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

    private func makeTerminal(cols: Int = 80, rows: Int = 24) -> Terminal {
        Terminal(delegate: HistoryTerminalDelegate(), options: TerminalOptions(cols: cols, rows: rows))
    }
}

private final class HistoryTerminalDelegate: TerminalDelegate {
    func send(source: Terminal, data: ArraySlice<UInt8>) {}
}
