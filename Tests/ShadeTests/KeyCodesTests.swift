import XCTest
import Carbon.HIToolbox
@testable import Shade
@testable import ShadeCore

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

    func testNamedKeyCodesMatchCarbon() {
        let expected: [(UInt16, Int)] = [
            (KeyCodes.tab, kVK_Tab), (KeyCodes.delete, kVK_Delete),
            (KeyCodes.home, kVK_Home), (KeyCodes.end, kVK_End),
            (KeyCodes.leftArrow, kVK_LeftArrow), (KeyCodes.rightArrow, kVK_RightArrow),
            (KeyCodes.upArrow, kVK_UpArrow), (KeyCodes.downArrow, kVK_DownArrow),
            (KeyCodes.pageUp, kVK_PageUp), (KeyCodes.pageDown, kVK_PageDown),
            (KeyCodes.equal, kVK_ANSI_Equal), (KeyCodes.minus, kVK_ANSI_Minus),
            (KeyCodes.zero, kVK_ANSI_0),
        ]
        for (value, carbon) in expected {
            XCTAssertEqual(Int(value), carbon)
        }
    }

    func testDigitAndLetterMapsMatchCarbon() {
        let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                      kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        let expectedDigits = Dictionary(uniqueKeysWithValues: digits.enumerated().map {
            (UInt16($0.element), $0.offset + 1)
        })
        XCTAssertEqual(KeyCodes.digitForKeyCode, expectedDigits)

        let letters = [kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_C, kVK_ANSI_D, kVK_ANSI_E, kVK_ANSI_F,
                       kVK_ANSI_G, kVK_ANSI_H, kVK_ANSI_I, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L,
                       kVK_ANSI_M, kVK_ANSI_N, kVK_ANSI_O, kVK_ANSI_P, kVK_ANSI_Q, kVK_ANSI_R,
                       kVK_ANSI_S, kVK_ANSI_T, kVK_ANSI_U, kVK_ANSI_V, kVK_ANSI_W, kVK_ANSI_X,
                       kVK_ANSI_Y, kVK_ANSI_Z]
        let expectedLetters = Dictionary(uniqueKeysWithValues: zip(letters, "abcdefghijklmnopqrstuvwxyz").map {
            (UInt16($0.0), $0.1)
        })
        XCTAssertEqual(KeyCodes.asciiLetterForKeyCode, expectedLetters)
    }

    func testAsciiMapIsAToZInclusive() {
        // Sanity: 26 entries, lowercase a–z, every keyCode unique.
        XCTAssertEqual(KeyCodes.asciiLetterForKeyCode.count, 26)
        let letters = Set(KeyCodes.asciiLetterForKeyCode.values)
        XCTAssertEqual(letters, Set("abcdefghijklmnopqrstuvwxyz"))
    }
}
