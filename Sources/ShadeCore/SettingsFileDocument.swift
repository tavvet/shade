import Foundation

/// The versioned `settings.json` document holding a `Preferences` snapshot.
public struct SettingsFileDocument: Codable {
    let version: Int
    let preferences: Preferences

    /// The version written by `encode`.
    static let currentVersion = 4

    public static func decode(_ data: Data) throws -> Preferences {
        let decoder = JSONDecoder()
        let header = try decoder.decode(Header.self, from: data)
        let migrated: Data
        switch header.version {
        case 1, 2, 3:
            guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  var preferences = json["preferences"] as? [String: Any] else {
                throw ConfigurationError.invalidPreferences
            }
            // Each step adds only the fields its version introduced, at their
            // defaults; every other field stays required.
            if header.version < 2 {
                preferences["tabMinimumWidth"] = Double(Preferences.defaults.tabMinimumWidth)
            }
            if header.version < 3 {
                preferences["backgroundHex"] = Preferences.defaults.backgroundHex
                preferences["foregroundHex"] = Preferences.defaults.foregroundHex
            }
            preferences["quitConfirmation"] = Preferences.defaults.quitConfirmation.rawValue
            json["preferences"] = preferences
            json["version"] = currentVersion
            migrated = try JSONSerialization.data(withJSONObject: json)
        case currentVersion:
            migrated = data
        default:
            throw ConfigurationError.unsupportedSettingsVersion(header.version)
        }
        var preferences = try decoder.decode(Self.self, from: migrated).preferences
        try validate(preferences)
        // A hand-edited file may use `#` or lowercase; keep the form local
        // defaults use so equal colors compare equal.
        normalizeHex(&preferences.backgroundHex)
        normalizeHex(&preferences.foregroundHex)
        normalizeHex(&preferences.linkHighlightHex)
        return preferences
    }

    private static func normalizeHex(_ value: inout String) {
        if let hex = Preferences.normalizedHex(value) { value = hex }
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
