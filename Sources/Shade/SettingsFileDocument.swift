import Foundation

struct SettingsFileDocument: Codable {
    let version: Int
    let preferences: Preferences

    static func decode(_ data: Data) throws -> Preferences {
        let document = try JSONDecoder().decode(Self.self, from: data)
        guard document.version == 1 else {
            throw ConfigurationError.unsupportedSettingsVersion(document.version)
        }
        try validate(document.preferences)
        return document.preferences
    }

    static func encode(_ preferences: Preferences) throws -> Data {
        try validate(preferences)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Self(version: 1, preferences: preferences))
    }

    private static func validate(_ value: Preferences) throws {
        guard (0.1...1).contains(value.widthFraction),
              (0.1...1).contains(value.heightFraction),
              (Preferences.minFontSize...Preferences.maxFontSize).contains(value.fontSize),
              (0.3...1).contains(value.backgroundOpacity),
              (0...0.5).contains(value.animationDuration),
              (1...600).contains(value.notifyThresholdSeconds),
              Preferences.parseHex(value.linkHighlightHex) != nil else {
            throw ConfigurationError.invalidPreferences
        }
    }
}
