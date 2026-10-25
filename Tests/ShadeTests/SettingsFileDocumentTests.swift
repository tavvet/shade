import XCTest
@testable import Shade
@testable import ShadeCore

final class SettingsFileDocumentTests: XCTestCase {
    func testRoundTripPreservesEveryPreference() throws {
        var preferences = Preferences.defaults
        preferences.fontName = "Menlo"
        preferences.fontSize = 18
        preferences.screenChoice = .main
        preferences.showInputSourceIndicator = true
        preferences.tabMinimumWidth = 180
        preferences.shellEnrichment = true
        preferences.backgroundHex = "1A2B3C"
        preferences.foregroundHex = "C0FFEE"

        XCTAssertEqual(try SettingsFileDocument.decode(SettingsFileDocument.encode(preferences)), preferences)
    }

    func testUnknownVersionAndMalformedValuesAreRejected() throws {
        let data = try SettingsFileDocument.encode(.defaults)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["version"] = 99
        XCTAssertThrowsError(try SettingsFileDocument.decode(JSONSerialization.data(withJSONObject: json)))

        json["version"] = SettingsFileDocument.currentVersion
        var preferences = try XCTUnwrap(json["preferences"] as? [String: Any])
        preferences["cursorShape"] = "unknown"
        json["preferences"] = preferences
        XCTAssertThrowsError(try SettingsFileDocument.decode(JSONSerialization.data(withJSONObject: json)))
    }

    func testMissingFieldsAndOutOfRangeNumbersAreRejected() throws {
        XCTAssertThrowsError(try SettingsFileDocument.decode(Data(#"{"version":1,"preferences":{}}"#.utf8)))
        var preferences = Preferences.defaults
        preferences.widthFraction = 4
        XCTAssertThrowsError(try SettingsFileDocument.encode(preferences))
        preferences = .defaults
        preferences.fontSize = .infinity
        XCTAssertThrowsError(try SettingsFileDocument.encode(preferences))
    }

    func testVersionOneMigratesTabWidthWithoutChangingOtherPreferences() throws {
        var expected = Preferences.defaults
        expected.fontSize = 18
        expected.backgroundOpacity = 0.6
        expected.showInputSourceIndicator = true
        var json = try XCTUnwrap(JSONSerialization.jsonObject(
            with: SettingsFileDocument.encode(expected)
        ) as? [String: Any])
        json["version"] = 1
        var preferences = try XCTUnwrap(json["preferences"] as? [String: Any])
        preferences.removeValue(forKey: "tabMinimumWidth")
        preferences.removeValue(forKey: "backgroundHex")
        preferences.removeValue(forKey: "foregroundHex")
        json["preferences"] = preferences

        let migrated = try SettingsFileDocument.decode(JSONSerialization.data(withJSONObject: json))

        XCTAssertEqual(migrated, expected)
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(
            with: SettingsFileDocument.encode(migrated)
        ) as? [String: Any])
        XCTAssertEqual(encoded["version"] as? Int, SettingsFileDocument.currentVersion)

        preferences.removeValue(forKey: "fontName")
        json["preferences"] = preferences
        XCTAssertThrowsError(try SettingsFileDocument.decode(JSONSerialization.data(withJSONObject: json)))
    }

    func testVersionTwoMigratesTheTerminalColorsWithoutChangingOtherPreferences() throws {
        var expected = Preferences.defaults
        expected.tabMinimumWidth = 200
        expected.backgroundOpacity = 0.6
        var json = try XCTUnwrap(JSONSerialization.jsonObject(
            with: SettingsFileDocument.encode(expected)
        ) as? [String: Any])
        json["version"] = 2
        var preferences = try XCTUnwrap(json["preferences"] as? [String: Any])
        preferences.removeValue(forKey: "backgroundHex")
        preferences.removeValue(forKey: "foregroundHex")
        json["preferences"] = preferences

        XCTAssertEqual(try SettingsFileDocument.decode(JSONSerialization.data(withJSONObject: json)), expected)

        preferences.removeValue(forKey: "tabMinimumWidth")
        json["preferences"] = preferences
        XCTAssertThrowsError(try SettingsFileDocument.decode(JSONSerialization.data(withJSONObject: json)))
    }

    func testCurrentVersionRequiresValidTerminalColors() throws {
        let data = try SettingsFileDocument.encode(.defaults)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let original = try XCTUnwrap(json["preferences"] as? [String: Any])
        for key in ["backgroundHex", "foregroundHex"] {
            var changed = json
            var preferences = original
            preferences.removeValue(forKey: key)
            changed["preferences"] = preferences
            XCTAssertThrowsError(try SettingsFileDocument.decode(JSONSerialization.data(withJSONObject: changed)), key)

            preferences[key] = "dark"
            changed["preferences"] = preferences
            XCTAssertThrowsError(try SettingsFileDocument.decode(JSONSerialization.data(withJSONObject: changed)), key)
        }
        var value = Preferences.defaults
        value.backgroundHex = "dark"
        XCTAssertThrowsError(try SettingsFileDocument.encode(value))
        value = .defaults
        value.foregroundHex = "light"
        XCTAssertThrowsError(try SettingsFileDocument.encode(value))
    }

    func testVersionTwoRequiresAValidTabWidth() throws {
        let data = try SettingsFileDocument.encode(.defaults)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var preferences = try XCTUnwrap(json["preferences"] as? [String: Any])
        preferences.removeValue(forKey: "tabMinimumWidth")
        json["preferences"] = preferences
        XCTAssertThrowsError(try SettingsFileDocument.decode(JSONSerialization.data(withJSONObject: json)))

        for width in [0.0, 300] {
            preferences["tabMinimumWidth"] = width
            json["preferences"] = preferences
            XCTAssertThrowsError(try SettingsFileDocument.decode(JSONSerialization.data(withJSONObject: json)))
        }
        for width in [0.0, 300, .infinity, .nan] {
            var value = Preferences.defaults
            value.tabMinimumWidth = width
            XCTAssertThrowsError(try SettingsFileDocument.encode(value))
        }
    }
}
