import AppKit
import XCTest
@testable import Shade

final class PanelTerminalInputResolverTests: XCTestCase {
    func testControlLettersUsePhysicalKeyCodes() {
        XCTAssertEqual(resolve(key("r"), flags: [.control]), .bytes([0x12]))
        XCTAssertEqual(resolve(key("r"), flags: [.control, .shift]), .bytes([0x12]))
        XCTAssertEqual(resolve(key("r"), flags: [.control, .capsLock]), .bytes([0x12]))
    }

    func testControlLettersWithAdditionalUserModifiersFallThrough() {
        XCTAssertNil(resolve(key("r"), flags: [.control, .option]))
        XCTAssertNil(resolve(key("r"), flags: [.control, .command]))
    }

    func testOptionDeleteProducesReadlineSequence() {
        XCTAssertEqual(resolve(KeyCodes.delete, flags: [.option]), .bytes([0x1B, 0x7F]))
        XCTAssertNil(resolve(KeyCodes.delete, flags: []))
        XCTAssertNil(resolve(KeyCodes.delete, flags: [.option, .shift]))
    }

    func testHomeAndEndProduceControlBytes() {
        XCTAssertEqual(resolve(KeyCodes.home, flags: []), .bytes([0x01]))
        XCTAssertEqual(resolve(KeyCodes.end, flags: [.function]), .bytes([0x05]))
        XCTAssertNil(resolve(KeyCodes.home, flags: [.shift, .function]))
    }

    func testPageKeysProduceXtermSequences() {
        XCTAssertEqual(resolve(KeyCodes.pageUp, flags: [.function]), .bytes([0x1B, 0x5B, 0x35, 0x7E]))
        XCTAssertEqual(resolve(KeyCodes.pageDown, flags: []), .bytes([0x1B, 0x5B, 0x36, 0x7E]))
        XCTAssertNil(resolve(KeyCodes.pageUp, flags: [.shift, .function]))
    }

    func testShiftArrowsExtendSelectionByCharacter() {
        XCTAssertEqual(
            resolve(KeyCodes.leftArrow, flags: [.shift, .function, .numericPad]),
            .selection(direction: .left, byWord: false)
        )
        XCTAssertEqual(
            resolve(KeyCodes.upArrow, flags: [.shift]),
            .selection(direction: .up, byWord: false)
        )
        XCTAssertEqual(
            resolve(KeyCodes.downArrow, flags: [.shift]),
            .selection(direction: .down, byWord: false)
        )
    }

    func testOptionShiftArrowsExtendSelectionByWord() {
        XCTAssertEqual(
            resolve(KeyCodes.rightArrow, flags: [.option, .shift]),
            .selection(direction: .right, byWord: true)
        )
    }

    func testCommandShiftHorizontalArrowsSelectToLineEdges() {
        XCTAssertEqual(
            resolve(KeyCodes.leftArrow, flags: [.command, .shift]),
            .selection(direction: .lineStart, byWord: false)
        )
        XCTAssertEqual(
            resolve(KeyCodes.rightArrow, flags: [.command, .shift]),
            .selection(direction: .lineEnd, byWord: false)
        )
        XCTAssertNil(resolve(KeyCodes.upArrow, flags: [.command, .shift]))
    }

    func testPlainArrowsAndUnrelatedKeysFallThrough() {
        XCTAssertNil(resolve(KeyCodes.leftArrow, flags: []))
        XCTAssertNil(resolve(KeyCodes.tab, flags: []))
    }

    private func resolve(
        _ keyCode: UInt16,
        flags: NSEvent.ModifierFlags
    ) -> PanelTerminalInput? {
        PanelTerminalInputResolver.resolve(keyCode: keyCode, modifierFlags: flags)
    }

    private func key(_ letter: Character) -> UInt16 {
        KeyCodes.asciiLetterForKeyCode.first(where: { $0.value == letter })!.key
    }
}
