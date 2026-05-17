import XCTest
import Carbon.HIToolbox
@testable import Shade

final class KeyCodesTests: XCTestCase {
    func testControlMaskedByteForR() {
        // Ctrl+R should always send DC2 (0x12) no matter the layout.
        XCTAssertEqual(KeyCodes.controlByte(forKeyCode: UInt16(kVK_ANSI_R)), 0x12)
    }

    func testControlMaskedByteForAandZ() {
        XCTAssertEqual(KeyCodes.controlByte(forKeyCode: UInt16(kVK_ANSI_A)), 0x01)
        XCTAssertEqual(KeyCodes.controlByte(forKeyCode: UInt16(kVK_ANSI_Z)), 0x1A)
    }

    func testNonLetterKeyCodesReturnNil() {
        // 36 == kVK_Return — not a letter row, no control byte mapping.
        XCTAssertNil(KeyCodes.controlByte(forKeyCode: UInt16(kVK_Return)))
        XCTAssertNil(KeyCodes.controlByte(forKeyCode: 999))
    }

    func testAsciiMapIsAToZInclusive() {
        // Sanity: 26 entries, lowercase a–z, every keyCode unique.
        XCTAssertEqual(KeyCodes.asciiLetterForKeyCode.count, 26)
        let letters = Set(KeyCodes.asciiLetterForKeyCode.values)
        XCTAssertEqual(letters, Set("abcdefghijklmnopqrstuvwxyz"))
    }
}
