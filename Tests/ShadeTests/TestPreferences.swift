import Foundation
@testable import Shade

/// Fixed preferences for tests, so no test reads the app's own configuration.
@MainActor
struct StaticPreferences: PreferencesProviding {
    var preferences = Preferences.defaults

    func load() -> Preferences { preferences }
}

/// A writable local store backed by a fresh, private defaults suite.
func isolatedPreferencesStore() -> PreferencesStore {
    PreferencesStore(userDefaults: UserDefaults(suiteName: "shade-tests-\(UUID().uuidString)")!)
}
