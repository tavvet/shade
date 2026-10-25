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
        guard let rgb = Self.parseHex(linkHighlightHex) else { return .systemYellow }
        return NSColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1.0)
    }

    mutating func setLinkHighlightColor(_ color: NSColor) {
        let srgb = color.usingColorSpace(.sRGB) ?? color
        linkHighlightHex = Self.hexString(for: .init(
            red: srgb.redComponent,
            green: srgb.greenComponent,
            blue: srgb.blueComponent
        ))
    }
}

extension Notification.Name {
    /// Posted only by `ConfigurationStore`, with the store as the object.
    static let shadePreferencesChanged = Notification.Name("ShadePreferencesChanged")
}
