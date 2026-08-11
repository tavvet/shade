import AppKit

/// Value snapshot of user-tunable layout, behavior and terminal appearance.
struct Preferences: Equatable {
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
    var shellEnrichment: Bool         // inject ZDOTDIR so a thin zsh gets completion + OSC 133 inside Shade
    var cursorShape: CursorShape      // block / bar / underline
    var cursorBlink: Bool             // blink the cursor
    var visualBell: Bool              // flash the terminal instead of relying on the audible bell

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

    enum CursorShape: String {
        case block, bar, underline

        /// Steady DECSCUSR parameter (CSI Ps SP q); the blinking variant is this minus one.
        var decscusrSteady: Int {
            switch self {
            case .block:     return 2
            case .underline: return 4
            case .bar:       return 6
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
        newTabInheritsCwd: false,
        shellEnrichment: false,
        cursorShape: .block,
        cursorBlink: false,
        visualBell: false
    )

    static let minFontSize: CGFloat = 8
    static let maxFontSize: CGFloat = 32

    /// Clamps a font size to the supported range (shared by `load` and zoom).
    static func clampFontSize(_ size: CGFloat) -> CGFloat {
        min(max(size, minFontSize), maxFontSize)
    }

    /// Next font size for a keyboard zoom step: `delta == nil` resets to the
    /// default size, otherwise adds `delta` points and clamps to range.
    static func zoomedFontSize(from current: CGFloat, delta: CGFloat?) -> CGFloat {
        guard let delta else { return defaults.fontSize }
        return clampFontSize(current + delta)
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

    mutating func setLinkHighlightColor(_ color: NSColor) {
        let srgb = color.usingColorSpace(.sRGB) ?? color
        let red = Int(round(srgb.redComponent * 255))
        let green = Int(round(srgb.greenComponent * 255))
        let blue = Int(round(srgb.blueComponent * 255))
        linkHighlightHex = String(format: "%02X%02X%02X", red, green, blue)
    }

    /// DECSCUSR escape (CSI Ps SP q) that sets the configured cursor shape + blink.
    var cursorDECSCUSR: String {
        let steady = cursorShape.decscusrSteady
        return "\u{1B}[\(cursorBlink ? steady - 1 : steady) q"
    }
}

extension Notification.Name {
    static let shadePreferencesChanged = Notification.Name("ShadePreferencesChanged")
}
