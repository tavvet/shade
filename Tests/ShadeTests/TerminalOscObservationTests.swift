import AppKit
import SwiftTerm
import XCTest
@testable import Shade

@MainActor
final class TerminalOscObservationTests: XCTestCase {
    func testEachMarkRetainsItsOwnPostDispatchRow() {
        let view = ActivityTerminalView(frame: .zero)
        view.resize(cols: 20, rows: 4)
        var events: [TerminalOscEvent] = []
        view.onOSC133 = { events.append($0) }
        view.feed(text: "one\u{1b}]133;A\u{7}two\r\n\u{1b}]133;D;0\u{7}")
        waitForCondition { events.count == 2 }
        XCTAssertEqual(events.map { String(decoding: $0.payload, as: UTF8.self) }, ["A", "D;0"])
        XCTAssertEqual(events.map(\.context?.bufferCursor.row), [1, 2])
    }

    func testOSCMaySpanInputChunksAndUTF8Scalars() {
        let view = ActivityTerminalView(frame: .zero)
        var payloads: [String] = []
        view.onOSC133 = { payloads.append(String(decoding: $0.payload, as: UTF8.self)) }
        let bytes = Array("\u{1b}]133;D;42;extension=界\u{1b}\\".utf8)
        for byte in bytes { view.feed(byteArray: [byte][...]) }
        waitForCondition { payloads.count == 1 }
        XCTAssertEqual(payloads, ["D;42;extension=界"])
    }

    func testC1TerminatorDispatchesBeforeFollowingText() {
        let view = ActivityTerminalView(frame: .zero)
        view.resize(cols: 20, rows: 4)
        var events: [TerminalOscEvent] = []
        view.onOSC133 = { events.append($0) }
        view.feed(byteArray: (Array("\u{1b}]133;A".utf8) + [0x9c] + Array("x".utf8))[...])
        waitForCondition { events.count == 1 }
        XCTAssertEqual(events.first?.payload, Array("A".utf8))
        XCTAssertEqual(view.visibleRowsText(0..<1), ["x"])
    }

    func testHiddenPTYReportsActivityAndOSCThroughNewAdapter() {
        let view = ActivityTerminalView(frame: .zero)
        var activity = 0
        var events: [TerminalOscEvent] = []
        view.onData = { activity += 1 }
        view.onOSC133 = { events.append($0) }
        view.startProcess(executable: "/bin/sh", args: ["-c", "printf '\\033]133;C\\007result\\r\\n\\033]133;D;0\\007'"])
        waitForCondition { activity > 0 && events.count == 2 }
        XCTAssertNil(view.window)
        XCTAssertEqual(events.map { String(decoding: $0.payload, as: UTF8.self) }, ["C", "D;0"])
    }
}
