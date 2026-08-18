import SwiftTerm
import XCTest
@testable import Shade

final class OSC133StreamObserverTests: XCTestCase {
    func testRecognizesBELAndSTTerminators() {
        var observer = OSC133StreamObserver()

        XCTAssertEqual(
            consume(Array("\u{1B}]133;A\u{07}".utf8), with: &observer),
            [Array("A".utf8)]
        )
        XCTAssertEqual(
            consume(Array("\u{1B}]133;D;17\u{1B}\\".utf8), with: &observer),
            [Array("D;17".utf8)]
        )
    }

    func testRecognizesC1StringTerminator() {
        var observer = OSC133StreamObserver()
        let bytes = Array("\u{1B}]133;A".utf8) + [0x9C]

        XCTAssertEqual(consume(bytes, with: &observer), [Array("A".utf8)])
    }

    func testUTF8ContinuationBytesDoNotStartControlStrings() {
        var observer = OSC133StreamObserver()
        let bytes = Array("Привет \u{1B}]133;C\u{07}".utf8)

        XCTAssertEqual(consume(bytes, with: &observer), [Array("C".utf8)])
    }

    func testIgnoresOtherAndMalformedOSCCodes() {
        var observer = OSC133StreamObserver()
        let bytes = Array((
            "\u{1B}]0;title\u{07}\u{1B}]oops;A\u{07}"
                + "\u{1B}]999999999999999999999999999999;A\u{07}"
        ).utf8)

        XCTAssertTrue(consume(bytes, with: &observer).isEmpty)
    }

    func testAcceptsLongZeroPaddedOSC133CodeLikeSwiftTerm() {
        var observer = OSC133StreamObserver()
        let bytes = Array("\u{1B}]0000000000133;A\u{07}".utf8)

        XCTAssertEqual(consume(bytes, with: &observer), [Array("A".utf8)])
    }

    func testC0AndDELKeepSwiftTermEscapeState() {
        var observer = OSC133StreamObserver()
        let bytes = [0x1B, 0x07, 0x7F, 0x5D] + Array("133;A".utf8) + [0x07]

        XCTAssertEqual(consume(bytes, with: &observer), [Array("A".utf8)])
    }

    func testEscapeTerminatesOSCBeforeStringTerminatorFinalByte() {
        var observer = OSC133StreamObserver()
        let bytes = Array("\u{1B}]133;A\u{1B}".utf8)

        XCTAssertEqual(consume(bytes, with: &observer), [Array("A".utf8)])
        XCTAssertTrue(consume([0x5C], with: &observer).isEmpty)
    }

    func testCarriesParserStateAcrossEveryChunkBoundary() {
        let sequence = Array("\u{1B}]133;D;127\u{1B}\\".utf8)

        for split in 0...sequence.count {
            var observer = OSC133StreamObserver()
            var payloads = consume(Array(sequence[..<split]), with: &observer)
            payloads += consume(Array(sequence[split...]), with: &observer)
            XCTAssertEqual(payloads, [Array("D;127".utf8)], "split at \(split)")
        }
    }

    func testOversizedPayloadIsDiscardedAndParserRecovers() {
        var observer = OSC133StreamObserver()
        let oversized = Array("\u{1B}]133;".utf8)
            + [UInt8](repeating: 0x41, count: 4_097)
            + [0x07]
        let valid = Array("\u{1B}]133;A\u{07}".utf8)

        XCTAssertEqual(consume(oversized + valid, with: &observer), [Array("A".utf8)])
    }

    @MainActor
    func testActivityViewReportsEachMarksOwnPostDispatchRow() {
        let view = ActivityTerminalView(frame: .zero)
        view.terminal.resize(cols: 20, rows: 4)
        var events: [(String, Int)] = []
        view.onOSC133 = { payload, row in
            events.append((String(decoding: payload, as: UTF8.self), row))
        }
        let bytes = Array(
            "one\u{1B}]133;A\u{07}two\r\n\u{1B}]133;D;0\u{07}".utf8
        )

        view.dataReceived(slice: bytes[...])

        XCTAssertEqual(events.map(\.0), ["A", "D;0"])
        XCTAssertEqual(events.map(\.1), [1, 2])
        XCTAssertEqual(view.terminal.semanticPromptMarks(at: 1).map(\.kind), [.initial])
    }

    @MainActor
    func testActivityViewHandlesOSCSpanningDataReceivedCalls() {
        let view = ActivityTerminalView(frame: .zero)
        view.terminal.resize(cols: 20, rows: 4)
        var payloads: [[UInt8]] = []
        view.onOSC133 = { payload, _ in payloads.append(payload) }
        let first = Array("\u{1B}]133;D".utf8)
        let second = Array(";42\u{1B}\\".utf8)

        view.dataReceived(slice: first[...])
        XCTAssertTrue(payloads.isEmpty)
        view.dataReceived(slice: second[...])

        XCTAssertEqual(payloads, [Array("D;42".utf8)])
    }

    @MainActor
    func testActivityViewDispatchesC1STThroughSwiftTermBeforeCallback() {
        let view = ActivityTerminalView(frame: .zero)
        view.terminal.resize(cols: 20, rows: 4)
        var payloads: [String] = []
        view.onOSC133 = { payload, _ in
            payloads.append(String(decoding: payload, as: UTF8.self))
        }
        let bytes = Array("\u{1B}]133;A".utf8) + [0x9C] + Array("x".utf8)

        view.dataReceived(slice: bytes[...])

        XCTAssertEqual(payloads, ["A"])
        XCTAssertEqual(view.terminal.semanticPromptMarks(at: 0).map(\.kind), [.initial])
        XCTAssertEqual(view.terminal.getCharacter(col: 0, row: 0), "x")
    }

    @MainActor
    func testScrollInvariantCursorSurvivesTrimmingAndScrolledViewport() {
        let view = ActivityTerminalView(frame: .zero)
        view.terminal.resize(cols: 12, rows: 2)
        view.terminal.changeScrollback(2)
        for index in 0..<8 {
            let bytes = Array("line-\(index)\r\n".utf8)
            view.dataReceived(slice: bytes[...])
        }
        view.scrollTo(row: 0)
        var observedRow: Int?
        view.onOSC133 = { _, row in observedRow = row }
        let mark = Array("\u{1B}]133;D;0\u{07}".utf8)

        view.dataReceived(slice: mark[...])

        XCTAssertGreaterThan(view.terminal.buffer.totalLinesTrimmed, 0)
        XCTAssertEqual(
            observedRow,
            view.terminal.buffer.totalLinesTrimmed
                + (TerminalBufferGeometry.lastBufferRow(in: view.terminal) ?? 0)
        )
    }

    private func consume(
        _ bytes: [UInt8],
        with observer: inout OSC133StreamObserver
    ) -> [[UInt8]] {
        bytes.compactMap { observer.consume($0) }
    }
}
