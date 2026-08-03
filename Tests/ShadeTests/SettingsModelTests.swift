import XCTest
@testable import Shade

final class SettingsModelTests: XCTestCase {
    func testReloadPreventsUnrelatedSaveFromOverwritingExternalFontZoom() async {
        await MainActor.run {
            let suite = "SettingsModelTests.\(UUID().uuidString)"
            let store = UserDefaults(suiteName: suite)!
            defer { store.removePersistentDomain(forName: suite) }

            store.set(13, forKey: Preferences.Key.fontSize)
            let model = SettingsModel(store: store, openAtLogin: false)

            store.set(14, forKey: Preferences.Key.fontSize)
            NotificationCenter.default.post(name: .shadePreferencesChanged, object: nil)
            XCTAssertEqual(model.fontSize, 14)

            model.visualBell.toggle()
            XCTAssertEqual(store.double(forKey: Preferences.Key.fontSize), 14)
        }
    }
}
