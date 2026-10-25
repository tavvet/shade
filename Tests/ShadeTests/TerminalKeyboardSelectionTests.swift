import AppKit
import SwiftTerm
import XCTest
@testable import Shade

@MainActor
final class TerminalKeyboardSelectionTests: XCTestCase {
    func testKeyboardRoutingAnchorsAtLiveCursorAndSelectsWideGlyph() {
        let view = TerminalView(frame: .zero, font: nil,
                                options: TerminalOptions(cols: 12, rows: 3))
        view.feed(text: "a界")
        view.extendShadeKeyboardSelection(direction: .left, byWord: false)
        XCTAssertEqual(view.getSelection(), "界")
        XCTAssertEqual(view.selectionSnapshot().start, Position(col: 3, row: 0))
    }

    func testCharacterSelectionTakesAWholeEmoji() {
        let view = TerminalView(frame: .zero, font: nil,
                                options: TerminalOptions(cols: 12, rows: 3))
        view.feed(text: "a😀")
        view.extendShadeKeyboardSelection(direction: .left, byWord: false)
        XCTAssertEqual(view.getSelection(), "😀")
        view.extendShadeKeyboardSelection(direction: .left, byWord: false)
        XCTAssertEqual(view.getSelection(), "a😀")
    }

    func testWordSelectionFollowsASoftWrappedWord() {
        let view = TerminalView(frame: .zero, font: nil,
                                options: TerminalOptions(cols: 6, rows: 4))
        // "one tw" fills the first row; "othree" continues on the wrapped row.
        view.feed(text: "one twothree")
        view.extendShadeKeyboardSelection(direction: .left, byWord: true)
        XCTAssertEqual(view.getSelection(), "twothree")
    }

    func testSelectionStartsAtTheLiveCursorWhileScrolledUp() {
        let view = TerminalView(frame: .zero, font: nil,
                                options: TerminalOptions(cols: 10, rows: 3))
        for line in 0..<20 { view.feed(text: "line\(line)\r\n") }
        view.feed(text: "end")
        let liveViewportRow = view.terminalStateSnapshot().viewportRow
        view.scroll(toPosition: 0)
        XCTAssertLessThan(view.terminalStateSnapshot().viewportRow, liveViewportRow)

        view.extendShadeKeyboardSelection(direction: .left, byWord: true)

        XCTAssertEqual(view.getSelection(), "end")
    }

    func testWordAndLineBoundaryRouting() {
        let view = TerminalView(frame: .zero, font: nil,
                                options: TerminalOptions(cols: 20, rows: 3))
        view.feed(text: "one two")
        view.extendShadeKeyboardSelection(direction: .left, byWord: true)
        XCTAssertEqual(view.getSelection(), "two")
        view.extendShadeKeyboardSelection(direction: .lineStart, byWord: false)
        XCTAssertEqual(view.getSelection(), "one two")
        view.selectNone()
        view.feed(text: "\u{1b}[1G")
        view.extendShadeKeyboardSelection(direction: .lineEnd, byWord: false)
        XCTAssertEqual(view.getSelection(), "one two")
    }
}
