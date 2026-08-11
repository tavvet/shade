import AppKit
import KeyboardShortcuts

@main
enum ShadeApp {
    static func main() {
        // LaunchServices starts GUI apps in "/". Shells should inherit $HOME.
        FileManager.default.changeCurrentDirectoryPath(NSHomeDirectory())

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

/// Coordinates application lifecycle and the top-level feature controllers.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let terminals = TerminalsController()
    private lazy var tabs = TabsObservable(controller: terminals)
    private lazy var keyboard = PanelKeyboardController(terminals: terminals)
    private lazy var panelContent = TerminalPanelContentController(terminals: terminals, tabs: tabs)

    private lazy var panel: DropdownPanel = {
        let panel = DropdownPanel()
        panel.keyHandler = keyboard
        panel.onBecomeKey = { [weak self] in
            guard let self else { return }
            self.panelContent.focusActiveTerminal()
            self.terminals.activeSession?.focusReturned()
        }
        panel.onWillShow = { [weak self] preferences in
            guard let self else { return }
            self.applyPreferences(preferences)
            self.notifications.panelWillShow(preferences: preferences)
        }
        panel.onShow = { [weak self] in self?.terminals.resumePolling() }
        panel.onHide = { [weak self] in self?.terminals.pausePolling() }
        return panel
    }()

    private lazy var menus = ApplicationMenuController(actions: self)
    private lazy var notifications = CommandNotificationCoordinator(terminals: terminals, panel: panel)
    private lazy var settings = SettingsWindowController()
    private lazy var about = AboutWindowController()
    private lazy var diagnostics = DiagnosticsWindowController(terminals: terminals)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The system's window-tab shortcuts would consume ⌘T before Shade's
        // own tab model gets a chance to handle it.
        NSWindow.allowsAutomaticWindowTabbing = false

        menus.install()
        panelContent.install(in: panel)
        notifications.start()
        primePanelFrame()
        terminals.ensureAtLeastOneSession()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesDidChange),
            name: .shadePreferencesChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
        KeyboardShortcuts.onKeyDown(for: .toggleShade) { [weak self] in
            self?.panel.toggle()
        }
    }

    /// Lays out the panel before the first shell starts so SwiftTerm computes
    /// its real row and column count instead of using its default buffer size.
    private func primePanelFrame() {
        let prefs = PreferencesStore.standard.load()
        guard let screen = prefs.resolvedScreen() else { return }
        panel.setFrame(prefs.dropdownFrame(on: screen), display: false)
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    @objc private func preferencesDidChange() {
        applyPreferences(PreferencesStore.standard.load())
    }

    private func applyPreferences(_ preferences: Preferences) {
        terminals.applyToAll(preferences)
        panel.apply(preferences)
        panelContent.apply(preferences)
    }

    /// Hide on a real app switch, but not during the transient resign-active
    /// event caused by opening one of Shade's own windows.
    @objc private func appDidResignActive() {
        guard PreferencesStore.standard.load().hideOnFocusLoss, panel.isVisible else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, !NSApp.isActive, self.panel.isVisible else { return }
            self.panel.hide()
        }
    }
}

extension AppDelegate: ApplicationMenuActions {
    func applicationMenuShowAbout() {
        about.present()
    }

    func applicationMenuShowSettings() {
        settings.present()
    }

    func applicationMenuShowDiagnostics() {
        diagnostics.present()
    }

    func applicationMenuCutSelection() {
        keyboard.cutSelection()
    }
}
