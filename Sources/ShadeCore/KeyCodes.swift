/// Maps macOS virtual key codes for letter rows on a US-ANSI layout to lowercase ASCII.
/// Used so that Control+R always sends 0x12 to the shell regardless of the user's input source
/// (SwiftTerm otherwise applies the control mask to whatever character the current layout
/// produces, which yields garbage on Cyrillic/Greek/etc).
public enum KeyCodes {
    // Named physical keyCodes for the non-letter keys Shade handles, as the
    // `UInt16` that `NSEvent.keyCode` exposes. They are fixed hardware codes,
    // written as numbers so this UI-free module needs no Carbon import;
    // `KeyCodesTests` checks every value against Carbon's `kVK_*` constants.
    // Letter keys go through `asciiLetterForKeyCode` below — letters matter
    // only when paired with a modifier, and the dict already handles the
    // layout-agnostic lookup we need at those call sites.
    public static let tab: UInt16 = 0x30         // kVK_Tab
    public static let delete: UInt16 = 0x33      // kVK_Delete
    public static let home: UInt16 = 0x73        // kVK_Home
    public static let end: UInt16 = 0x77         // kVK_End
    public static let leftArrow: UInt16 = 0x7B   // kVK_LeftArrow
    public static let rightArrow: UInt16 = 0x7C  // kVK_RightArrow
    public static let upArrow: UInt16 = 0x7E     // kVK_UpArrow
    public static let downArrow: UInt16 = 0x7D   // kVK_DownArrow
    public static let pageUp: UInt16 = 0x74      // kVK_PageUp
    public static let pageDown: UInt16 = 0x79    // kVK_PageDown
    // Number-row keys for font zoom (⌘= / ⌘− / ⌘0). Matched by physical
    // position so they work on any layout.
    public static let equal: UInt16 = 0x18       // kVK_ANSI_Equal
    public static let minus: UInt16 = 0x1B       // kVK_ANSI_Minus
    public static let zero: UInt16 = 0x1D        // kVK_ANSI_0

    /// Number-row quick slots stay stable across keyboard layouts, just like
    /// Shade's letter shortcuts below (kVK_ANSI_1…kVK_ANSI_9).
    public static let digitForKeyCode: [UInt16: Int] = [
        0x12: 1, 0x13: 2, 0x14: 3, 0x15: 4, 0x17: 5,
        0x16: 6, 0x1A: 7, 0x1C: 8, 0x19: 9,
    ]

    /// kVK_ANSI_A…kVK_ANSI_Z.
    public static let asciiLetterForKeyCode: [UInt16: Character] = [
        0x00: "a", 0x0B: "b", 0x08: "c", 0x02: "d", 0x0E: "e", 0x03: "f",
        0x05: "g", 0x04: "h", 0x22: "i", 0x26: "j", 0x28: "k", 0x25: "l",
        0x2E: "m", 0x2D: "n", 0x1F: "o", 0x23: "p", 0x0C: "q", 0x0F: "r",
        0x01: "s", 0x11: "t", 0x20: "u", 0x09: "v", 0x0D: "w", 0x07: "x",
        0x10: "y", 0x06: "z",
    ]

    /// Translate a letter keyCode under the Control modifier into the canonical control byte
    /// (Ctrl+A = 0x01, Ctrl+R = 0x12, etc).
    public static func controlByte(forKeyCode keyCode: UInt16) -> UInt8? {
        guard let letter = asciiLetterForKeyCode[keyCode],
              let ascii = letter.asciiValue else { return nil }
        return ascii - 0x60
    }
}
