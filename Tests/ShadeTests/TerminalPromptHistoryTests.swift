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

    private func makeTerminal() -> Terminal {
        Terminal(delegate: HistoryTerminalDelegate(), options: TerminalOptions(cols: 80, rows: 24))
    }
}

private final class HistoryTerminalDelegate: TerminalDelegate {
    func send(source: Terminal, data: ArraySlice<UInt8>) {}
}
