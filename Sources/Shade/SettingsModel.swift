import AppKit
import SwiftUI

/// Observable editing state for the settings window.
///
/// The persisted values live in one `Preferences` snapshot so loading, editing
/// and saving cannot drift across parallel lists of properties.
@MainActor
final class SettingsModel: NSObject, ObservableObject {
    @Published var preferences: Preferences {
        didSet { preferencesDidChange(from: oldValue) }
    }

    @Published var openAtLogin: Bool {
        didSet {
            guard oldValue != openAtLogin, !suppressOpenAtLoginWrite else { return }
            applyOpenAtLogin()
        }
    }

    var linkHighlightColor: Binding<Color> {
        Binding(
            get: { Color(nsColor: self.preferences.linkHighlightColor()) },
            set: { self.preferences.setLinkHighlightColor(NSColor($0)) }
        )
    }

    private let preferencesStore: PreferencesStore
    private let loginItemManager: any LoginItemManaging
    private let notificationAuthorizationRequester: any NotificationAuthorizationRequesting
    private var suppressPreferenceWrites = false
    private var suppressOpenAtLoginWrite = false
    private var applyDebounce: Task<Void, Never>?

    init(
        store: UserDefaults = .standard,
        openAtLogin: Bool? = nil,
        loginItemManager: any LoginItemManaging = SystemLoginItemManager(),
        notificationAuthorizationRequester: any NotificationAuthorizationRequesting =
            SystemNotificationAuthorizationRequester()
    ) {
        let preferencesStore = PreferencesStore(userDefaults: store)
        self.preferencesStore = preferencesStore
        self.loginItemManager = loginItemManager
        self.notificationAuthorizationRequester = notificationAuthorizationRequester
        preferences = preferencesStore.load()
        self.openAtLogin = openAtLogin ?? loginItemManager.isEnabled
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesChanged),
            name: .shadePreferencesChanged,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Refresh both persisted preferences and macOS-owned state before the
    /// Settings window is presented again.
    func reloadForPresentation() {
        reloadPreferences()
        suppressOpenAtLoginWrite = true
        defer { suppressOpenAtLoginWrite = false }
        openAtLogin = loginItemManager.isEnabled
    }

    /// Re-read values changed outside this model, such as keyboard font zoom or
    /// `defaults write`, without echoing the assignment back to UserDefaults.
    private func reloadPreferences() {
        suppressPreferenceWrites = true
        defer { suppressPreferenceWrites = false }
        preferences = preferencesStore.load()
    }

    private func preferencesDidChange(from oldValue: Preferences) {
        guard !suppressPreferenceWrites else { return }
        preferencesStore.save(preferences)
        if preferences.notifyOnCommandFinish, !oldValue.notifyOnCommandFinish {
            notificationAuthorizationRequester.requestAuthorizationIfNeeded()
        }
        scheduleApply()
    }

    @objc private func preferencesChanged(_ notification: Notification) {
        if let source = notification.object as AnyObject?, source === self { return }
        reloadPreferences()
    }

    private func applyOpenAtLogin() {
        do {
            try loginItemManager.setEnabled(openAtLogin)
        } catch {
            NSLog("Shade: open-at-login change failed: %@", String(describing: error))
            // Revert the toggle without re-firing didSet.
            suppressOpenAtLoginWrite = true
            openAtLogin = loginItemManager.isEnabled
            suppressOpenAtLoginWrite = false
        }
    }

    /// Coalesce the live re-apply. Slider and color-picker drags persist every
    /// value immediately, but the expensive terminal relayout waits for a pause.
    private func scheduleApply() {
        applyDebounce?.cancel()
        applyDebounce = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            NotificationCenter.default.post(name: .shadePreferencesChanged, object: self)
        }
    }
}
