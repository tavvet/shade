import Foundation
@testable import Shade

/// Fixed preferences for tests, so no test reads the app's own configuration.
@MainActor
struct StaticPreferences: PreferencesProviding {
    var preferences = Preferences.defaults

    func load() -> Preferences { preferences }
}

/// Preferences a test can change after handing the provider to a component.
@MainActor
final class MutablePreferences: PreferencesProviding {
    var preferences = Preferences.defaults

    func load() -> Preferences { preferences }
}

/// A writable local store backed by a fresh, private defaults suite.
func isolatedPreferencesStore() -> PreferencesStore {
    PreferencesStore(userDefaults: UserDefaults(suiteName: "shade-tests-\(UUID().uuidString)")!)
}

extension TerminalLaunchConfiguration {
    /// Keeps the command wrapper waiting until the test terminates the tab, so
    /// it never continues into the developer's login shell and dotfiles.
    static var waitingForTermination: TerminalLaunchConfiguration {
        TerminalLaunchConfiguration(
            initialCommand: ProcessInvocation(executable: "/bin/sleep", arguments: ["30"])
        )
    }
}
