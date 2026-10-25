import AppKit
import ShadeCore

extension Preferences.BlurMaterial {
    var nsMaterial: NSVisualEffectView.Material {
        switch self {
        case .hud:         return .hudWindow
        case .underWindow: return .underWindowBackground
        case .sidebar:     return .sidebar
        case .fullScreen:  return .fullScreenUI
        }
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
        Self.color(hex: linkHighlightHex, fallback: .systemYellow)
    }

    mutating func setLinkHighlightColor(_ color: NSColor) {
        linkHighlightHex = Self.hex(for: color)
    }

    /// The terminal's default background with the configured opacity.
    func terminalBackgroundColor() -> NSColor {
        let fallback = Self.color(hex: Self.defaults.backgroundHex, fallback: .black)
        return Self.color(hex: backgroundHex, fallback: fallback)
            .withAlphaComponent(backgroundOpacity)
    }

    mutating func setTerminalBackgroundColor(_ color: NSColor) {
        backgroundHex = Self.hex(for: color)
    }

    /// sRGB color for a stored `RRGGBB` value, or `fallback` when it is invalid.
    static func color(hex: String, fallback: NSColor) -> NSColor {
        guard let rgb = parseHex(hex) else { return fallback }
        return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1.0)
    }

    /// Uppercase `RRGGBB` for `color` in sRGB; alpha is dropped.
    static func hex(for color: NSColor) -> String {
        let srgb = color.usingColorSpace(.sRGB) ?? color
        return hexString(for: .init(
            red: srgb.redComponent,
            green: srgb.greenComponent,
            blue: srgb.blueComponent
        ))
    }
}
