import Foundation

/// The versioned `settings.json` document holding a `Preferences` snapshot.
public struct SettingsFileDocument: Codable {
    let version: Int
    let preferences: Preferences

    /// The version written by `encode`.
    static let currentVersion = 3

    public static func decode(_ data: Data) throws -> Preferences {
        let decoder = JSONDecoder()
        let header = try decoder.decode(Header.self, from: data)
        let migrated: Data
        switch header.version {
        case 1, 2:
            guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  var preferences = json["preferences"] as? [String: Any] else {
                throw ConfigurationError.invalidPreferences
            }
            // Each step adds only the fields its version introduced, at their
            // defaults; every other field stays required.
            if header.version < 2 {
                preferences["tabMinimumWidth"] = Double(Preferences.defaults.tabMinimumWidth)
            }
            preferences["backgroundHex"] = Preferences.defaults.backgroundHex
            preferences["foregroundHex"] = Preferences.defaults.foregroundHex
            json["preferences"] = preferences
            json["version"] = currentVersion
            migrated = try JSONSerialization.data(withJSONObject: json)
        case currentVersion:
            migrated = data
        default:
            throw ConfigurationError.unsupportedSettingsVersion(header.version)
        }
        let document = try decoder.decode(Self.self, from: migrated)
        try validate(document.preferences)
        return document.preferences
    }

    public static func encode(_ preferences: Preferences) throws -> Data {
        try validate(preferences)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Self(version: currentVersion, preferences: preferences))
    }

    private struct Header: Decodable {
        let version: Int
    }

    private static func validate(_ value: Preferences) throws {
        guard (0.1...1).contains(value.widthFraction),
              (0.1...1).contains(value.heightFraction),
              (Preferences.minFontSize...Preferences.maxFontSize).contains(value.fontSize),
              (Preferences.minTabWidth...Preferences.maxTabWidth).contains(value.tabMinimumWidth),
              (0.3...1).contains(value.backgroundOpacity),
              (0...0.5).contains(value.animationDuration),
              (1...600).contains(value.notifyThresholdSeconds),
              Preferences.parseHex(value.linkHighlightHex) != nil,
              Preferences.parseHex(value.backgroundHex) != nil,
              Preferences.parseHex(value.foregroundHex) != nil else {
            throw ConfigurationError.invalidPreferences
        }
    }
}
