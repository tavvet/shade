import XCTest
import SwiftTerm
@testable import Shade

final class PromptMarkTests: XCTestCase {
    // MARK: - Pure payload parsing

    func testParsesPromptStart() {
        XCTAssertEqual(
            PromptMark.parse(payload: Array("A".utf8)[...], row: 5),
            PromptMark(kind: .promptStart, row: 5))
    }

    func testParsesPromptEnd() {
        XCTAssertEqual(
            PromptMark.parse(payload: Array("B".utf8)[...], row: 7),
            PromptMark(kind: .promptEnd, row: 7))
    }

    func testParsesCommandStart() {
        XCTAssertEqual(
            PromptMark.parse(payload: Array("C".utf8)[...], row: 12),
            PromptMark(kind: .commandStart, row: 12))
    }

    func testParsesCommandDoneWithZeroExit() {
        XCTAssertEqual(
            PromptMark.parse(payload: Array("D;0".utf8)[...], row: 14),
            PromptMark(kind: .commandDone(exitCode: 0), row: 14))
    }

    func testParsesCommandDoneWithNonzeroExit() {
        XCTAssertEqual(
            PromptMark.parse(payload: Array("D;127".utf8)[...], row: 20),
            PromptMark(kind: .commandDone(exitCode: 127), row: 20))
    }

    func testParsesCommandDoneWithoutExit() {
        XCTAssertEqual(
            PromptMark.parse(payload: Array("D".utf8)[...], row: 22),
            PromptMark(kind: .commandDone(exitCode: nil), row: 22))
    }

    func testIgnoresExtraSpecTokens() {
        // Spec allows `;P;aid=…` style trailers; we should accept the mark.
        XCTAssertEqual(
            PromptMark.parse(payload: Array("A;P;aid=42".utf8)[...], row: 1),
            PromptMark(kind: .promptStart, row: 1))
    }

    func testRejectsUnknownKind() {
        XCTAssertNil(PromptMark.parse(payload: Array("X".utf8)[...], row: 0))
    }

    func testRejectsMultiCharLeadToken() {
        // Guard against accidentally accepting payloads like "Apple" as A.
        XCTAssertNil(PromptMark.parse(payload: Array("AB".utf8)[...], row: 0))
    }

    func testRejectsEmptyPayload() {
        XCTAssertNil(PromptMark.parse(payload: ArraySlice<UInt8>(), row: 0))
    }

    // MARK: - Navigation helpers

    func testPreviousPromptStartReturnsHighestPromptStartBelowCutoff() {
        let marks: [PromptMark] = [
            PromptMark(kind: .promptStart, row: 10),
            PromptMark(kind: .promptStart, row: 20),
            PromptMark(kind: .promptStart, row: 30),
        ]
        XCTAssertEqual(PromptMark.previousPromptStart(before: 25, in: marks)?.row, 20)
        XCTAssertEqual(PromptMark.previousPromptStart(before: 100, in: marks)?.row, 30)
    }

    func testPreviousPromptStartExcludesMarkAtExactCutoff() {
        // "Before cutoff" means strictly less than — anchoring on viewport top
        // shouldn't return the mark that's already there.
        let marks = [PromptMark(kind: .promptStart, row: 25)]
        XCTAssertNil(PromptMark.previousPromptStart(before: 25, in: marks))
    }

    func testPreviousPromptStartReturnsNilWhenNoMarksBelow() {
        let marks = [PromptMark(kind: .promptStart, row: 50)]
        XCTAssertNil(PromptMark.previousPromptStart(before: 10, in: marks))
    }

    func testPreviousPromptStartIgnoresNonPromptStartMarks() {
        // Only `A` (.promptStart) marks count as navigation targets;
        // B/C/D mark other phases of the same prompt and shouldn't be jumped to.
        let marks: [PromptMark] = [
            PromptMark(kind: .promptStart, row: 10),
            PromptMark(kind: .promptEnd, row: 15),
            PromptMark(kind: .commandStart, row: 20),
            PromptMark(kind: .commandDone(exitCode: 0), row: 25),
        ]
        XCTAssertEqual(PromptMark.previousPromptStart(before: 30, in: marks)?.row, 10)
    }

    func testPreviousPromptStartHandlesUnsortedArray() {
        // After `clear`, cursor y resets to 0 in the viewport, so a new mark
        // can be recorded with a row lower than older entries.
        let marks: [PromptMark] = [
            PromptMark(kind: .promptStart, row: 50),
            PromptMark(kind: .promptStart, row: 10),
            PromptMark(kind: .promptStart, row: 30),
        ]
        XCTAssertEqual(PromptMark.previousPromptStart(before: 40, in: marks)?.row, 30)
    }

    func testNextPromptStartReturnsLowestPromptStartAboveCutoff() {
        let marks: [PromptMark] = [
            PromptMark(kind: .promptStart, row: 10),
            PromptMark(kind: .promptStart, row: 20),
            PromptMark(kind: .promptStart, row: 30),
        ]
        XCTAssertEqual(PromptMark.nextPromptStart(after: 15, in: marks)?.row, 20)
        XCTAssertEqual(PromptMark.nextPromptStart(after: 0, in: marks)?.row, 10)
    }

    func testNextPromptStartReturnsNilWhenNoMarksAbove() {
        let marks = [PromptMark(kind: .promptStart, row: 5)]
        XCTAssertNil(PromptMark.nextPromptStart(after: 100, in: marks))
    }

    func testNextPromptStartIgnoresNonPromptStartMarks() {
        let marks: [PromptMark] = [
            PromptMark(kind: .promptEnd, row: 15),
            PromptMark(kind: .commandDone(exitCode: 1), row: 20),
            PromptMark(kind: .promptStart, row: 25),
        ]
        XCTAssertEqual(PromptMark.nextPromptStart(after: 10, in: marks)?.row, 25)
    }

    // MARK: - Last command output range

    func testLastCommandOutputRangeForTypicalPair() {
        let marks: [PromptMark] = [
            PromptMark(kind: .promptStart, row: 5),
            PromptMark(kind: .commandStart, row: 7),
            PromptMark(kind: .commandDone(exitCode: 0), row: 12),
        ]
        XCTAssertEqual(PromptMark.lastCommandOutputRange(in: marks), 7..<12)
    }

    func testLastCommandOutputRangeUsesLatestPairWhenMultiple() {
        let marks: [PromptMark] = [
            PromptMark(kind: .commandStart, row: 5),
            PromptMark(kind: .commandDone(exitCode: 0), row: 8),
            PromptMark(kind: .commandStart, row: 10),
            PromptMark(kind: .commandDone(exitCode: 1), row: 14),
        ]
        XCTAssertEqual(PromptMark.lastCommandOutputRange(in: marks), 10..<14)
    }

    func testLastCommandOutputRangeReturnsNilForEmptyOutput() {
        // Command emitted C and D on the same row (no output produced).
        let marks: [PromptMark] = [
            PromptMark(kind: .commandStart, row: 7),
            PromptMark(kind: .commandDone(exitCode: 0), row: 7),
        ]
        XCTAssertNil(PromptMark.lastCommandOutputRange(in: marks))
    }

    func testLastCommandOutputRangeReturnsNilWhenCommandInFlight() {
        // C without a following D — command is still running.
        let marks: [PromptMark] = [
            PromptMark(kind: .commandStart, row: 5),
        ]
        XCTAssertNil(PromptMark.lastCommandOutputRange(in: marks))
    }

    func testLastCommandOutputRangeReturnsNilWhenDLacksPrecedingC() {
        // Defensive: D with no preceding C in the array (shouldn't happen
        // with well-behaved shell integration, but don't crash on it).
        let marks: [PromptMark] = [
            PromptMark(kind: .promptStart, row: 5),
            PromptMark(kind: .commandDone(exitCode: 0), row: 10),
        ]
        XCTAssertNil(PromptMark.lastCommandOutputRange(in: marks))
    }

    func testLastCommandOutputRangeMatchesByChronologyAfterClear() {
        // `clear` resets cursor.y, so a newer C can have a row LOWER than
        // an older D. We still want the chronologically latest C/D pair.
        let marks: [PromptMark] = [
            PromptMark(kind: .commandStart, row: 40),
            PromptMark(kind: .commandDone(exitCode: 0), row: 48),
            // clear happens here — cursor moves back to top of viewport.
            PromptMark(kind: .commandStart, row: 2),
            PromptMark(kind: .commandDone(exitCode: 0), row: 5),
        ]
        XCTAssertEqual(PromptMark.lastCommandOutputRange(in: marks), 2..<5)
    }

    // MARK: - End-to-end through SwiftTerm

    func testSwiftTermDispatchesOsc133AndReportsCursorRow() {
        let delegate = NoopTerminalDelegate()
        let terminal = Terminal(delegate: delegate, options: TerminalOptions(cols: 80, rows: 24))
        var seenPayloads: [String] = []
        var seenRows: [Int] = []
        terminal.registerOscHandler(code: 133) { data in
            seenRows.append(terminal.scrollInvariantCursorRow)
            seenPayloads.append(String(bytes: data, encoding: .utf8) ?? "")
        }

        // Two linefeeds → cursor on row 2 (0-indexed). Then OSC 133 ; A BEL.
        terminal.feed(text: "hi\r\nthere\r\n")
        let osc: [UInt8] = [0x1B, 0x5D] + Array("133;A".utf8) + [0x07]
        terminal.feed(byteArray: osc)

        XCTAssertEqual(seenPayloads, ["A"])
        XCTAssertEqual(seenRows, [2])

        // Now emit OSC 133 ; D ; 0 — different payload, same row.
        let oscDone: [UInt8] = [0x1B, 0x5D] + Array("133;D;0".utf8) + [0x07]
        terminal.feed(byteArray: oscDone)
        XCTAssertEqual(seenPayloads, ["A", "D;0"])
        XCTAssertEqual(seenRows.last, 2)
    }
}

/// Minimal TerminalDelegate for tests — only `send` lacks a default impl.
private final class NoopTerminalDelegate: TerminalDelegate {
    func send(source: Terminal, data: ArraySlice<UInt8>) {}
}
