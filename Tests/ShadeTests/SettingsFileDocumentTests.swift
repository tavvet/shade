import XCTest
@testable import Shade

final class SettingsFileDocumentTests: XCTestCase {
    func testRoundTripPreservesEveryPreference() throws {
        var preferences = Preferences.defaults
        preferences.fontName = "Menlo"
        preferences.fontSize = 18
        preferences.screenChoice = .main
        preferences.showInputSourceIndicator = true
        preferences.shellEnrichment = true

        XCTAssertEqual(try SettingsFileDocument.decode(SettingsFileDocument.encode(preferences)), preferences)
    }

    func testUnknownVersionAndMalformedValuesAreRejected() throws {
        let data = try SettingsFileDocument.encode(.defaults)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["version"] = 99
        XCTAssertThrowsError(try SettingsFileDocument.decode(JSONSerialization.data(withJSONObject: json)))

        json["version"] = 1
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
}
