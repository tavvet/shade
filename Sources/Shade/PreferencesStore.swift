import Foundation

/// Persists the complete Preferences snapshot in UserDefaults. Validation
/// happens while loading so every consumer receives values inside the ranges
/// supported by the UI and terminal renderer.
struct PreferencesStore {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    static var standard: PreferencesStore { PreferencesStore() }

    func load() -> Preferences {
        var preferences = Preferences.defaults
        if userDefaults.object(forKey: Key.widthFraction) != nil {
            preferences.widthFraction = clampFraction(userDefaults.double(forKey: Key.widthFraction))
        }
        if userDefaults.object(forKey: Key.heightFraction) != nil {
            preferences.heightFraction = clampFraction(userDefaults.double(forKey: Key.heightFraction))
        }
        if let raw = userDefaults.string(forKey: Key.horizontalAlignment),
           let value = Preferences.HorizontalAlignment(rawValue: raw) {
            preferences.horizontalAlignment = value
        }
        if let raw = userDefaults.string(forKey: Key.screenChoice),
           let value = Preferences.ScreenChoice(rawValue: raw) {
            preferences.screenChoice = value
        }
        if userDefaults.object(forKey: Key.fontSize) != nil {
            preferences.fontSize = Preferences.clampFontSize(
                CGFloat(userDefaults.double(forKey: Key.fontSize))
            )
        }
        if let raw = userDefaults.string(forKey: Key.fontName) {
            preferences.fontName = raw
        }
        if userDefaults.object(forKey: Key.backgroundOpacity) != nil {
            preferences.backgroundOpacity = min(
                max(userDefaults.double(forKey: Key.backgroundOpacity), 0.3),
                1.0
            )
        }
        if userDefaults.object(forKey: Key.animationDuration) != nil {
            preferences.animationDuration = min(
                max(userDefaults.double(forKey: Key.animationDuration), 0.0),
                0.5
            )
        }
        if let raw = userDefaults.string(forKey: Key.linkHighlightHex),
           Preferences.parseHex(raw) != nil {
            preferences.linkHighlightHex = normalize(hex: raw)
        }
        if userDefaults.object(forKey: Key.backgroundBlur) != nil {
            preferences.backgroundBlur = userDefaults.bool(forKey: Key.backgroundBlur)
        }
        if userDefaults.object(forKey: Key.notifyOnCommandFinish) != nil {
            preferences.notifyOnCommandFinish = userDefaults.bool(forKey: Key.notifyOnCommandFinish)
        }
        if userDefaults.object(forKey: Key.notifyThresholdSeconds) != nil {
            preferences.notifyThresholdSeconds = min(
                max(userDefaults.double(forKey: Key.notifyThresholdSeconds), 1),
                600
            )
        }
        if userDefaults.object(forKey: Key.hideOnFocusLoss) != nil {
            preferences.hideOnFocusLoss = userDefaults.bool(forKey: Key.hideOnFocusLoss)
        }
        if let raw = userDefaults.string(forKey: Key.blurMaterial),
           let value = Preferences.BlurMaterial(rawValue: raw) {
            preferences.blurMaterial = value
        }
        if userDefaults.object(forKey: Key.newTabInheritsCwd) != nil {
            preferences.newTabInheritsCwd = userDefaults.bool(forKey: Key.newTabInheritsCwd)
        }
        if userDefaults.object(forKey: Key.shellEnrichment) != nil {
            preferences.shellEnrichment = userDefaults.bool(forKey: Key.shellEnrichment)
        }
        if let raw = userDefaults.string(forKey: Key.cursorShape),
           let value = Preferences.CursorShape(rawValue: raw) {
            preferences.cursorShape = value
        }
        if userDefaults.object(forKey: Key.cursorBlink) != nil {
            preferences.cursorBlink = userDefaults.bool(forKey: Key.cursorBlink)
        }
        if userDefaults.object(forKey: Key.visualBell) != nil {
            preferences.visualBell = userDefaults.bool(forKey: Key.visualBell)
        }
        return preferences
    }

    func save(_ preferences: Preferences) {
        userDefaults.set(preferences.widthFraction, forKey: Key.widthFraction)
        userDefaults.set(preferences.heightFraction, forKey: Key.heightFraction)
        userDefaults.set(preferences.horizontalAlignment.rawValue, forKey: Key.horizontalAlignment)
        userDefaults.set(preferences.screenChoice.rawValue, forKey: Key.screenChoice)
        userDefaults.set(preferences.fontSize, forKey: Key.fontSize)
        userDefaults.set(preferences.fontName, forKey: Key.fontName)
        userDefaults.set(preferences.backgroundOpacity, forKey: Key.backgroundOpacity)
        userDefaults.set(preferences.animationDuration, forKey: Key.animationDuration)
        userDefaults.set(preferences.linkHighlightHex, forKey: Key.linkHighlightHex)
        userDefaults.set(preferences.backgroundBlur, forKey: Key.backgroundBlur)
        userDefaults.set(preferences.notifyOnCommandFinish, forKey: Key.notifyOnCommandFinish)
        userDefaults.set(preferences.notifyThresholdSeconds, forKey: Key.notifyThresholdSeconds)
        userDefaults.set(preferences.hideOnFocusLoss, forKey: Key.hideOnFocusLoss)
        userDefaults.set(preferences.blurMaterial.rawValue, forKey: Key.blurMaterial)
        userDefaults.set(preferences.newTabInheritsCwd, forKey: Key.newTabInheritsCwd)
        userDefaults.set(preferences.shellEnrichment, forKey: Key.shellEnrichment)
        userDefaults.set(preferences.cursorShape.rawValue, forKey: Key.cursorShape)
        userDefaults.set(preferences.cursorBlink, forKey: Key.cursorBlink)
        userDefaults.set(preferences.visualBell, forKey: Key.visualBell)
    }

    /// Persists keyboard font zoom without rewriting unrelated values that may
    /// have been changed concurrently through `defaults` or another process.
    func saveFontSize(_ fontSize: CGFloat) {
        userDefaults.set(fontSize, forKey: Key.fontSize)
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
        static let shellEnrichment = "shellEnrichment"
        static let cursorShape = "cursorShape"
        static let cursorBlink = "cursorBlink"
        static let visualBell = "visualBell"
    }

    private func normalize(hex: String) -> String {
        var value = hex.uppercased()
        if value.hasPrefix("#") { value.removeFirst() }
        return value
    }

    private func clampFraction(_ value: Double) -> CGFloat {
        CGFloat(min(max(value, 0.1), 1.0))
    }
}
