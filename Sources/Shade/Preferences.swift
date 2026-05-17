import AppKit

/// User-tunable layout and appearance for the dropdown panel.
/// Persisted via standard `defaults`; reloaded on every show()/notification so CLI edits apply instantly.
struct Preferences {
    var widthFraction: CGFloat
    var heightFraction: CGFloat
    var horizontalAlignment: HorizontalAlignment
    var screenChoice: ScreenChoice

    var fontSize: CGFloat
    var fontName: String              // "" = system monospaced
    var backgroundOpacity: Double     // 0.3 – 1.0
    var animationDuration: Double     // 0.0 – 0.5 seconds

    enum HorizontalAlignment: String {
        case left, center, right
    }

    enum ScreenChoice: String {
        case main
        case mouseLocation
    }

    static let defaults = Preferences(
        widthFraction: 1.0,
        heightFraction: 0.4,
        horizontalAlignment: .center,
        screenChoice: .mouseLocation,
        fontSize: 13,
        fontName: "",
        backgroundOpacity: 0.94,
        animationDuration: 0.16
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
        if store.object(forKey: Key.fontSize) != nil {
            prefs.fontSize = CGFloat(min(max(store.double(forKey: Key.fontSize), 8), 32))
        }
        if let raw = store.string(forKey: Key.fontName) {
            prefs.fontName = raw
        }
        if store.object(forKey: Key.backgroundOpacity) != nil {
            prefs.backgroundOpacity = min(max(store.double(forKey: Key.backgroundOpacity), 0.3), 1.0)
        }
        if store.object(forKey: Key.animationDuration) != nil {
            prefs.animationDuration = min(max(store.double(forKey: Key.animationDuration), 0.0), 0.5)
        }
        return prefs
    }

    enum Key {
        static let widthFraction = "widthFraction"
        static let heightFraction = "heightFraction"
        static let horizontalAlignment = "horizontalAlignment"
        static let screenChoice = "screenChoice"
        static let fontSize = "fontSize"
        static let fontName = "fontName"
        static let backgroundOpacity = "backgroundOpacity"
        static let animationDuration = "animationDuration"
    }

    private static func clampFraction(_ value: Double) -> CGFloat {
        CGFloat(min(max(value, 0.1), 1.0))
    }
}

extension Preferences {
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

    func terminalFont() -> NSFont {
        if !fontName.isEmpty, let font = NSFont(name: fontName, size: fontSize) {
            return font
        }
        return NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }
}

extension Notification.Name {
    static let shadePreferencesChanged = Notification.Name("ShadePreferencesChanged")
}
