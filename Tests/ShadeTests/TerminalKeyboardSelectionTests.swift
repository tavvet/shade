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
