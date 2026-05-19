import AppKit
import Carbon.HIToolbox

/// Maps macOS virtual key codes for letter rows on a US-ANSI layout to lowercase ASCII.
/// Used so that Control+R always sends 0x12 to the shell regardless of the user's input source
/// (SwiftTerm otherwise applies the control mask to whatever character the current layout
/// produces, which yields garbage on Cyrillic/Greek/etc).
enum KeyCodes {
    // Named physical keyCodes for the non-letter keys Shade handles. Values
    // come from Carbon's HIToolbox so they stay authoritative; we just wrap
    // them in `UInt16` (the type `NSEvent.keyCode` exposes) and a clearer
    // name. Letter keys go through `asciiLetterForKeyCode` below — letters
    // matter only when paired with a modifier, and the dict already handles
    // the layout-agnostic lookup we need at those call sites.
    static let tab: UInt16 = UInt16(kVK_Tab)
    static let delete: UInt16 = UInt16(kVK_Delete)
    static let home: UInt16 = UInt16(kVK_Home)
    static let end: UInt16 = UInt16(kVK_End)
    static let leftArrow: UInt16 = UInt16(kVK_LeftArrow)
    static let rightArrow: UInt16 = UInt16(kVK_RightArrow)
    static let upArrow: UInt16 = UInt16(kVK_UpArrow)
    static let downArrow: UInt16 = UInt16(kVK_DownArrow)

    static let asciiLetterForKeyCode: [UInt16: Character] = [
        UInt16(kVK_ANSI_A): "a", UInt16(kVK_ANSI_B): "b", UInt16(kVK_ANSI_C): "c",
        UInt16(kVK_ANSI_D): "d", UInt16(kVK_ANSI_E): "e", UInt16(kVK_ANSI_F): "f",
        UInt16(kVK_ANSI_G): "g", UInt16(kVK_ANSI_H): "h", UInt16(kVK_ANSI_I): "i",
        UInt16(kVK_ANSI_J): "j", UInt16(kVK_ANSI_K): "k", UInt16(kVK_ANSI_L): "l",
        UInt16(kVK_ANSI_M): "m", UInt16(kVK_ANSI_N): "n", UInt16(kVK_ANSI_O): "o",
        UInt16(kVK_ANSI_P): "p", UInt16(kVK_ANSI_Q): "q", UInt16(kVK_ANSI_R): "r",
        UInt16(kVK_ANSI_S): "s", UInt16(kVK_ANSI_T): "t", UInt16(kVK_ANSI_U): "u",
        UInt16(kVK_ANSI_V): "v", UInt16(kVK_ANSI_W): "w", UInt16(kVK_ANSI_X): "x",
        UInt16(kVK_ANSI_Y): "y", UInt16(kVK_ANSI_Z): "z",
    ]

    /// Translate a letter keyCode under the Control modifier into the canonical control byte
    /// (Ctrl+A = 0x01, Ctrl+R = 0x12, etc).
    static func controlByte(forKeyCode keyCode: UInt16) -> UInt8? {
        guard let letter = asciiLetterForKeyCode[keyCode],
              let ascii = letter.asciiValue else { return nil }
        return ascii - 0x60
    }
}
