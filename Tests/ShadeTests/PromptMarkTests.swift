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

    func testAcceptsValidSemanticOptions() {
        XCTAssertEqual(
            PromptMark.parse(
                payload: Array("A;k=i;cl=w;click_events=2;special_key=1".utf8)[...],
                row: 3
            ),
            PromptMark(kind: .promptStart, row: 3)
        )
    }

    func testRejectsKnownSemanticOptionWithInvalidValue() {
        XCTAssertNil(
            PromptMark.parse(payload: Array("A;k=bogus".utf8)[...], row: 3)
        )
        XCTAssertNil(
            PromptMark.parse(payload: Array("C;click_events=3".utf8)[...], row: 3)
        )
    }

    func testDoesNotCreateNavigationMarksForGroupedPromptKinds() {
        for payload in ["A;k=r", "A;k=c", "A;k=s"] {
            XCTAssertNil(PromptMark.parse(payload: Array(payload.utf8)[...], row: 3))
        }
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

    @MainActor
    func testActivityViewObservesOsc133AfterSwiftTermDispatch() {
        let view = ActivityTerminalView(frame: .zero)
        view.terminal.resize(cols: 80, rows: 24)
        var seenPayloads: [String] = []
        var seenRows: [Int] = []
        view.onOSC133 = { data, row in
            seenRows.append(row)
            seenPayloads.append(String(bytes: data, encoding: .utf8) ?? "")
        }

        // Two linefeeds → cursor on row 2 (0-indexed). Then OSC 133 ; A BEL.
        let bytes = Array("hi\r\nthere\r\n\u{1B}]133;A\u{07}".utf8)
        view.dataReceived(slice: bytes[...])

        XCTAssertEqual(seenPayloads, ["A"])
        XCTAssertEqual(seenRows, [2])
        XCTAssertEqual(view.terminal.semanticPromptMarks(at: 2).map(\.kind), [.initial])

        // Now emit OSC 133 ; D ; 0 — different payload, same row.
        let oscDone: [UInt8] = [0x1B, 0x5D] + Array("133;D;0".utf8) + [0x07]
        view.dataReceived(slice: oscDone[...])
        XCTAssertEqual(seenPayloads, ["A", "D;0"])
        XCTAssertEqual(seenRows.last, 2)
    }
}
