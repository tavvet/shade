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

    /// The terminal's default background with the configured opacity.
    func terminalBackgroundColor() -> NSColor {
        Self.color(hex: backgroundHex, fallback: .black).withAlphaComponent(backgroundOpacity)
    }

    /// The default text color; programs may still pick their own colors.
    func terminalForegroundColor() -> NSColor {
        Self.color(hex: foregroundHex, fallback: .white)
    }

    /// sRGB color for a stored `RRGGBB` value, or `fallback` when it is invalid.
    static func color(hex: String, fallback: NSColor) -> NSColor {
        guard let rgb = parseHex(hex) else { return fallback }
        return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1.0)
    }

    /// Uppercase `RRGGBB` for `color` in sRGB, dropping alpha; nil for colors
    /// with no sRGB form, such as patterns.
    static func hex(for color: NSColor) -> String? {
        guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
        return hexString(for: .init(
            red: srgb.redComponent,
            green: srgb.greenComponent,
            blue: srgb.blueComponent
        ))
    }
}
