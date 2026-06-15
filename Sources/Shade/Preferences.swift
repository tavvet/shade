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
    var linkHighlightHex: String      // 6-char RRGGBB; falls back to systemYellow if invalid
    var backgroundBlur: Bool          // frosted-glass backdrop behind the translucent terminal
    var notifyOnCommandFinish: Bool   // notify when a long command finishes while the panel is hidden
    var notifyThresholdSeconds: Double // minimum command duration (seconds) to notify
    var hideOnFocusLoss: Bool         // auto-hide the panel when Shade stops being the active app
    var blurMaterial: BlurMaterial    // NSVisualEffectView material for the background blur
    var newTabInheritsCwd: Bool       // ⌘T opens in the active tab's directory instead of $HOME

    enum HorizontalAlignment: String {
        case left, center, right
    }

    enum ScreenChoice: String {
        case main
        case mouseLocation
    }

    enum BlurMaterial: String {
        case hud, underWindow, sidebar, fullScreen

        var nsMaterial: NSVisualEffectView.Material {
            switch self {
            case .hud:         return .hudWindow
            case .underWindow: return .underWindowBackground
            case .sidebar:     return .sidebar
            case .fullScreen:  return .fullScreenUI
            }
        }
    }

    static let defaults = Preferences(
        widthFraction: 1.0,
        heightFraction: 0.4,
        horizontalAlignment: .center,
        screenChoice: .mouseLocation,
        fontSize: 13,
        fontName: "",
        backgroundOpacity: 0.94,
        animationDuration: 0.16,
        linkHighlightHex: "FFCC00",     // ≈ NSColor.systemYellow
        backgroundBlur: true,
        notifyOnCommandFinish: false,
        notifyThresholdSeconds: 30,
        hideOnFocusLoss: false,
        blurMaterial: .hud,
        newTabInheritsCwd: false
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
        if let raw = store.string(forKey: Key.linkHighlightHex),
           Self.parseHex(raw) != nil {
            prefs.linkHighlightHex = Self.normalize(hex: raw)
        }
        if store.object(forKey: Key.backgroundBlur) != nil {
            prefs.backgroundBlur = store.bool(forKey: Key.backgroundBlur)
        }
        if store.object(forKey: Key.notifyOnCommandFinish) != nil {
            prefs.notifyOnCommandFinish = store.bool(forKey: Key.notifyOnCommandFinish)
        }
        if store.object(forKey: Key.notifyThresholdSeconds) != nil {
            prefs.notifyThresholdSeconds = min(max(store.double(forKey: Key.notifyThresholdSeconds), 1), 600)
        }
        if store.object(forKey: Key.hideOnFocusLoss) != nil {
            prefs.hideOnFocusLoss = store.bool(forKey: Key.hideOnFocusLoss)
        }
        if let raw = store.string(forKey: Key.blurMaterial),
           let value = BlurMaterial(rawValue: raw) {
            prefs.blurMaterial = value
        }
        if store.object(forKey: Key.newTabInheritsCwd) != nil {
            prefs.newTabInheritsCwd = store.bool(forKey: Key.newTabInheritsCwd)
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
        static let linkHighlightHex = "linkHighlightHex"
        static let backgroundBlur = "backgroundBlur"
        static let notifyOnCommandFinish = "notifyOnCommandFinish"
        static let notifyThresholdSeconds = "notifyThresholdSeconds"
        static let hideOnFocusLoss = "hideOnFocusLoss"
        static let blurMaterial = "blurMaterial"
        static let newTabInheritsCwd = "newTabInheritsCwd"
    }

    /// Parses a 6-char `RRGGBB` (with or without leading `#`) into an NSColor.
    /// Returns nil for any other shape — caller should fall back to a default.
    static func parseHex(_ raw: String) -> NSColor? {
        var s = raw.uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        return NSColor(
            red:   CGFloat((value >> 16) & 0xFF) / 255.0,
            green: CGFloat((value >> 8)  & 0xFF) / 255.0,
            blue:  CGFloat( value        & 0xFF) / 255.0,
            alpha: 1.0
        )
    }

    private static func normalize(hex: String) -> String {
        var s = hex.uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        return s
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

    func linkHighlightColor() -> NSColor {
        Self.parseHex(linkHighlightHex) ?? .systemYellow
    }
}

extension Notification.Name {
    static let shadePreferencesChanged = Notification.Name("ShadePreferencesChanged")
}
