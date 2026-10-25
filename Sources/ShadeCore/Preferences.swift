import Foundation

/// Value snapshot of user-tunable layout, behavior and terminal appearance.
/// AppKit projections (screen, frame, font, colors) live in the app target.
public struct Preferences: Codable, Equatable, Sendable {
    public var widthFraction: CGFloat
    public var heightFraction: CGFloat
    public var horizontalAlignment: HorizontalAlignment
    public var screenChoice: ScreenChoice

    public var fontSize: CGFloat
    public var fontName: String              // "" = system monospaced
    public var backgroundOpacity: Double     // 0.3 – 1.0
    public var backgroundHex: String         // 6-char RRGGBB terminal background; opacity applies on top
    public var foregroundHex: String         // 6-char RRGGBB default text color
    public var animationDuration: Double     // 0.0 – 0.5 seconds
    public var linkHighlightHex: String      // 6-char RRGGBB; falls back to systemYellow if invalid
    public var backgroundBlur: Bool          // frosted-glass backdrop behind the translucent terminal
    public var showInputSourceIndicator: Bool // show the current keyboard input source in the tab bar
    public var tabMinimumWidth: CGFloat      // minimum clickable width of each tab, in points
    public var notifyOnCommandFinish: Bool   // notify when a long command finishes while the panel is hidden
    public var notifyThresholdSeconds: Double // minimum command duration (seconds) to notify
    public var hideOnFocusLoss: Bool         // auto-hide the panel when Shade stops being the active app
    public var blurMaterial: BlurMaterial    // background blur material
    public var newTabInheritsCwd: Bool       // ⌘T opens in the active tab's directory instead of $HOME
    public var shellEnrichment: Bool         // inject ZDOTDIR so a thin zsh gets completion + OSC 133 inside Shade
    public var cursorShape: CursorShape      // block / bar / underline
    public var cursorBlink: Bool             // blink the cursor
    public var visualBell: Bool              // flash the terminal instead of relying on the audible bell

    public enum HorizontalAlignment: String, Codable, Sendable {
        case left, center, right
    }

    public enum ScreenChoice: String, Codable, Sendable {
        case main
        case mouseLocation
    }

    public enum BlurMaterial: String, Codable, Sendable {
        case hud, underWindow, sidebar, fullScreen
    }

    public enum CursorShape: String, Codable, Sendable {
        case block, bar, underline
    }

    /// An sRGB color with components in 0…1.
    public struct RGB: Equatable, Sendable {
        public let red: Double
        public let green: Double
        public let blue: Double

        public init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    public static let defaults = Preferences(
        widthFraction: 1.0,
        heightFraction: 0.4,
        horizontalAlignment: .center,
        screenChoice: .mouseLocation,
        fontSize: 13,
        fontName: "",
        backgroundOpacity: 0.94,
        backgroundHex: "141414",
        foregroundHex: "EBEBEB",
        animationDuration: 0.16,
        linkHighlightHex: "FFCC00",     // ≈ NSColor.systemYellow
        backgroundBlur: true,
        showInputSourceIndicator: false,
        tabMinimumWidth: 120,
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

    public static let minFontSize: CGFloat = 8
    public static let maxFontSize: CGFloat = 32
    public static let minTabWidth: CGFloat = 80
    public static let maxTabWidth: CGFloat = 240

    public static func clampTabMinimumWidth(_ width: CGFloat) -> CGFloat {
        guard width.isFinite else { return defaults.tabMinimumWidth }
        return min(max(width, minTabWidth), maxTabWidth)
    }

    /// Clamps a font size to the supported range (shared by `load` and zoom).
    public static func clampFontSize(_ size: CGFloat) -> CGFloat {
        min(max(size, minFontSize), maxFontSize)
    }

    /// Next font size for a keyboard zoom step: `delta == nil` resets to the
    /// default size, otherwise adds `delta` points and clamps to range.
    public static func zoomedFontSize(from current: CGFloat, delta: CGFloat?) -> CGFloat {
        guard let delta else { return defaults.fontSize }
        return clampFontSize(current + delta)
    }

    /// Parses a 6-char `RRGGBB` (with or without leading `#`).
    /// Returns nil for any other shape — caller should fall back to a default.
    public static func parseHex(_ raw: String) -> RGB? {
        var s = raw.uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        return RGB(
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0
        )
    }

    /// Formats sRGB components in 0…1 as uppercase `RRGGBB`.
    public static func hexString(for color: RGB) -> String {
        func byte(_ component: Double) -> Int {
            Int((min(max(component, 0), 1) * 255).rounded())
        }
        return String(format: "%02X%02X%02X", byte(color.red), byte(color.green), byte(color.blue))
    }
}
