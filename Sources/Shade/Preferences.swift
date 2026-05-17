import AppKit

/// User-tunable layout for the dropdown panel.
/// Persisted via standard `defaults`; reloaded on every show() so CLI edits apply instantly.
struct Preferences {
    var widthFraction: CGFloat
    var heightFraction: CGFloat
    var horizontalAlignment: HorizontalAlignment
    var screenChoice: ScreenChoice

    enum HorizontalAlignment: String {
        case left, center, right
    }

    enum ScreenChoice: String {
        /// `NSScreen.main` — the screen with the menu bar / key window.
        case main
        /// The screen currently containing the mouse cursor.
        case mouseLocation
    }

    static let defaults = Preferences(
        widthFraction: 1.0,
        heightFraction: 0.4,
        horizontalAlignment: .center,
        screenChoice: .mouseLocation
    )

    static func load(from store: UserDefaults = .standard) -> Preferences {
        var prefs = defaults
        if store.object(forKey: Key.widthFraction) != nil {
            prefs.widthFraction = clampFraction(store.double(forKey: Key.widthFraction))
        }
        if store.object(forKey: Key.heightFraction) != nil {
            prefs.heightFraction = clampFraction(store.double(forKey: Key.heightFraction))
        }
        if let raw = store.string(forKey: Key.horizontalAlignment),
           let value = HorizontalAlignment(rawValue: raw) {
            prefs.horizontalAlignment = value
        }
        if let raw = store.string(forKey: Key.screenChoice),
           let value = ScreenChoice(rawValue: raw) {
            prefs.screenChoice = value
        }
        return prefs
    }

    private enum Key {
        static let widthFraction = "widthFraction"
        static let heightFraction = "heightFraction"
        static let horizontalAlignment = "horizontalAlignment"
        static let screenChoice = "screenChoice"
    }

    private static func clampFraction(_ value: Double) -> CGFloat {
        CGFloat(min(max(value, 0.1), 1.0))
    }
}

extension Preferences {
    /// Returns the target screen, falling back to `.main` if the chosen heuristic finds nothing.
    @MainActor
    func resolvedScreen() -> NSScreen? {
        switch screenChoice {
        case .main:
            return NSScreen.main
        case .mouseLocation:
            let mouse = NSEvent.mouseLocation
            return NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        }
    }

    /// Final visible frame for the dropdown on the target screen.
    func dropdownFrame(on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let width = (visible.width * widthFraction).rounded()
        let height = (visible.height * heightFraction).rounded()
        let x: CGFloat
        switch horizontalAlignment {
        case .left:   x = visible.minX
        case .center: x = visible.minX + (visible.width - width) / 2
        case .right:  x = visible.maxX - width
        }
        return NSRect(x: x, y: visible.maxY - height, width: width, height: height)
    }
}
