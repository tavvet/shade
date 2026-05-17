import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// The global hotkey that toggles the drop-down panel. Defaults to F12 (Guake-style).
    static let toggleShade = Self("toggleShade", default: .init(.f12))
}
