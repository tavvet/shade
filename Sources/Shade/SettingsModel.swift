import AppKit
import SwiftUI
import ShadeCore

/// Observable editing state for the settings window.
///
/// The persisted values live in one `Preferences` snapshot so loading, editing
/// and saving cannot drift across parallel lists of properties.
@MainActor
final class SettingsModel: NSObject, ObservableObject {
    @Published var persistenceError: String?
    @Published private(set) var isSaving = false
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
        colorBinding(\.linkHighlightHex, fallback: .systemYellow)
    }

    /// Background color without opacity; the opacity slider stays separate.
    var terminalBackgroundColor: Binding<Color> {
        colorBinding(\.backgroundHex, fallback: .black)
    }

    var terminalForegroundColor: Binding<Color> {
        colorBinding(\.foregroundHex, fallback: .white)
    }

    /// The exact color last chosen for each hex preference. Returning it while
    /// the stored hex still matches keeps the picker from being reset to the
    /// 8-bit rounded value on every drag step, which makes its sliders jump.
    private var pickedColors: [WritableKeyPath<Preferences, String>: (hex: String, color: Color)] = [:]

    private func colorBinding(
        _ hexKey: WritableKeyPath<Preferences, String> & Sendable,
        fallback: NSColor
    ) -> Binding<Color> {
        Binding(
            get: {
                let hex = self.preferences[keyPath: hexKey]
                if let picked = self.pickedColors[hexKey], picked.hex == hex {
                    return picked.color
                }
                return Color(nsColor: Preferences.color(hex: hex, fallback: fallback))
            },
            set: { color in
                let picked = NSColor(color)
                guard let hex = Preferences.hex(for: picked) else { return }
                let opaque = picked.alphaComponent == 1
                    ? color
                    : Color(nsColor: picked.withAlphaComponent(1))
                self.pickedColors[hexKey] = (hex, opaque)
                self.preferences[keyPath: hexKey] = hex
            }
        )
    }

    private let preferencesStore: any PreferencesStoring
    private let loginItemManager: any LoginItemManaging
    private let notificationAuthorizationRequester: any NotificationAuthorizationRequesting
    private var suppressPreferenceWrites = false
    private var suppressOpenAtLoginWrite = false
    private var saveTask: Task<Void, Never>?
    private var savedPreferences: Preferences

    init(
        preferences preferencesStore: any PreferencesStoring,
        openAtLogin: Bool? = nil,
        loginItemManager: any LoginItemManaging = SystemLoginItemManager(),
        notificationAuthorizationRequester: any NotificationAuthorizationRequesting =
            SystemNotificationAuthorizationRequester()
    ) {
        self.preferencesStore = preferencesStore
        self.loginItemManager = loginItemManager
        self.notificationAuthorizationRequester = notificationAuthorizationRequester
        let loaded = preferencesStore.load()
        preferences = loaded
        savedPreferences = loaded
        self.openAtLogin = openAtLogin ?? loginItemManager.isEnabled
        super.init()
        // Follow only this model's own store; a store that never announces
        // (such as a plain local defaults store) needs no observation.
        if let sender = preferencesStore.preferencesChangeSender {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(preferencesChanged),
                name: .shadePreferencesChanged,
                object: sender
            )
        }
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
        guard !isSaving else { return }
        suppressPreferenceWrites = true
        defer { suppressPreferenceWrites = false }
        preferences = preferencesStore.load()
        savedPreferences = preferences
    }

    private func preferencesDidChange(from oldValue: Preferences) {
        guard !suppressPreferenceWrites else { return }
        guard preferences != oldValue else { return }
        guard saveTask == nil else { return }
        isSaving = true
        saveTask = Task { @MainActor in
            // One write at a time. Slider changes arriving during I/O become
            // the next candidate, based only on the last successful save. The
            // store announces each successful save; the model never posts.
            while preferences != savedPreferences {
                let candidate = preferences
                let previous = savedPreferences
                do {
                    try await preferencesStore.save(candidate, replacing: previous)
                    savedPreferences = candidate
                    persistenceError = nil
                    if candidate.notifyOnCommandFinish, !previous.notifyOnCommandFinish {
                        notificationAuthorizationRequester.requestAuthorizationIfNeeded()
                    }
                } catch {
                    persistenceError = error.localizedDescription
                    _ = await preferencesStore.reload()
                    break
                }
            }
            isSaving = false
            saveTask = nil
            reloadPreferences()
        }
    }

    func waitForPendingSave() async { await saveTask?.value }

    @objc private func preferencesChanged(_ notification: Notification) {
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
}
