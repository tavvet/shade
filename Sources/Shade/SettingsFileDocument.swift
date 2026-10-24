import Foundation

struct SettingsFileDocument: Codable {
    let version: Int
    let preferences: Preferences

    static func decode(_ data: Data) throws -> Preferences {
        let decoder = JSONDecoder()
        let header = try decoder.decode(Header.self, from: data)
        let migrated: Data
        switch header.version {
        case 1:
            guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  var preferences = json["preferences"] as? [String: Any] else {
                throw ConfigurationError.invalidPreferences
            }
            preferences["tabMinimumWidth"] = Double(Preferences.defaults.tabMinimumWidth)
            json["preferences"] = preferences
            json["version"] = 2
            migrated = try JSONSerialization.data(withJSONObject: json)
        case 2:
            migrated = data
        default:
            throw ConfigurationError.unsupportedSettingsVersion(header.version)
        }
        let document = try decoder.decode(Self.self, from: migrated)
        try validate(document.preferences)
        return document.preferences
    }

    static func encode(_ preferences: Preferences) throws -> Data {
        try validate(preferences)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Self(version: 2, preferences: preferences))
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
              Preferences.parseHex(value.linkHighlightHex) != nil else {
            throw ConfigurationError.invalidPreferences
        }
    }
}
