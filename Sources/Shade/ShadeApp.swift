import AppKit
import KeyboardShortcuts

@main
enum ShadeApp {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--verify-resource-bundles") {
            exit(BundleVerification.run() ? EXIT_SUCCESS : EXIT_FAILURE)
        }

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
    /// The single preferences source passed to every feature controller.
    private let configuration: ConfigurationStore
    private let terminals: TerminalsController
    private let inputSource = InputSourceMonitor()
    private lazy var connections = SSHConnectionsController(
        store: ConfigurationSSHProfileStore(configuration: configuration)
    ) { [weak self] profile in
        guard let self else { return }
        try self.terminals.connect(to: profile)
        // A connection may originate in Settings while the picker is also open.
        // Defer teardown so a picker button can finish its SwiftUI action first.
        DispatchQueue.main.async { [weak self] in
            self?.connectionPicker?.dismiss()
        }
        if self.panel.isVisible {
            self.panel.makeKeyAndOrderFront(nil)
        } else {
            self.panel.show()
        }
    }
    private lazy var tabs = TabsObservable(controller: terminals)
    private lazy var keyboard = PanelKeyboardController(
        terminals: terminals,
        preferences: configuration,
        showConnections: { [weak self] in self?.presentConnectionPicker() },
        connectQuickSlot: { [weak self] number in
            self?.connectQuickSlot(number)
        }
    )
    private lazy var panelContent = TerminalPanelContentController(
        terminals: terminals,
        tabs: tabs,
        inputSource: inputSource
    )
    private var connectionPicker: SSHConnectionPickerPresenter?
    private var quickSlotTask: Task<Void, Never>?
    private var settingsWerePresented = false

    private lazy var panel: DropdownPanel = {
        let panel = DropdownPanel(preferences: configuration)
        panel.keyHandler = keyboard
        panel.onBecomeKey = { [weak self] in
            guard let self else { return }
            // macOS can restore an app-specific input source during activation.
            // Refresh after the panel becomes key so the badge reflects that
            // final source even if the transition did not emit a notification.
            self.inputSource.refresh()
            self.panelContent.focusActiveTerminal()
            self.terminals.activeSession?.focusReturned()
        }
        panel.onWillShow = { [weak self] preferences in
            guard let self else { return }
            Task { await self.connections.reload() }
            self.terminals.ensureAtLeastOneSession()
            self.applyPreferences(preferences)
            self.notifications.panelWillShow(preferences: preferences)
        }
        panel.onShow = { [weak self] in self?.terminals.resumePolling() }
        panel.onHide = { [weak self] in
            self?.quickSlotTask?.cancel()
            self?.connectionPicker?.dismiss()
            self?.terminals.pausePolling()
        }
        return panel
    }()

    private lazy var menus = ApplicationMenuController(actions: self)
    private lazy var notifications = CommandNotificationCoordinator(
        terminals: terminals,
        panel: panel,
        preferences: configuration
    )
    private lazy var settings = SettingsWindowController(connections: connections)
    private lazy var about = AboutWindowController()
    private lazy var diagnostics = DiagnosticsWindowController(
        terminals: terminals,
        inputSource: inputSource
    )

    override init() {
        let configuration = ConfigurationStore.shared
        self.configuration = configuration
        terminals = TerminalsController(preferences: configuration)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The system's window-tab shortcuts would consume ⌘T before Shade's
        // own tab model gets a chance to handle it.
        NSWindow.allowsAutomaticWindowTabbing = false

        menus.install()
        panelContent.install(in: panel, preferences: configuration.load())
        notifications.start()
        primePanelFrame()

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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(configurationDidChange),
            name: ConfigurationStore.didChange,
            object: configuration
        )
        KeyboardShortcuts.onKeyDown(for: .toggleShade) { [weak self] in
            self?.panel.toggle()
        }
        // Start with portable preferences when available. F12 remains usable
        // during a slow initial read and can create a session from the fallback.
        Task { @MainActor in
            await connections.reload()
            if !panel.isVisible { primePanelFrame() }
            terminals.ensureAtLeastOneSession()
        }
    }

    /// Lays out the panel before the first shell starts so SwiftTerm computes
    /// its real row and column count instead of using its default buffer size.
    private func primePanelFrame() {
        let prefs = configuration.load()
        guard let screen = prefs.resolvedScreen() else { return }
        panel.setFrame(prefs.dropdownFrame(on: screen), display: false)
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    @objc private func preferencesDidChange() {
        applyPreferences(configuration.load())
    }

    @objc private func configurationDidChange() {
        connections.invalidateLibrary()
        Task { await connections.reload() }
    }

    private func applyPreferences(_ preferences: Preferences) {
        terminals.applyToAll(preferences)
        panel.apply(preferences)
        panelContent.apply(preferences)
    }

    private func presentConnectionPicker() {
        Task { await connections.reload() }
        if panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.show()
        }

        if connectionPicker == nil {
            connectionPicker = SSHConnectionPickerPresenter(
                controller: connections,
                openConnectionSettings: { [weak self] in
                    guard let self else { return }
                    self.presentSettings(page: .connections)
                }
            )
        }
        connectionPicker?.present(over: panel)
    }

    private func connectQuickSlot(_ number: Int) {
        quickSlotTask?.cancel()
        quickSlotTask = Task { @MainActor in
            await connections.reload()
            guard !Task.isCancelled, panel.isVisible else { return }
            _ = connections.connectQuickSlot(number)
        }
    }

    private func prepareForAuxiliaryWindow() {
        connectionPicker?.dismiss()
        panel.hide()
    }

    private func presentSettings(page: SettingsPage? = nil) {
        prepareForAuxiliaryWindow()
        settingsWerePresented = true
        settings.present(page: page)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        quickSlotTask?.cancel()
        Task { @MainActor in
            // Let tasks accepted by the last button/key action enter their queues.
            await Task.yield()
            if settingsWerePresented { await settings.waitForPendingSave() }
            await connections.waitForPendingSave()
            await keyboard.waitForPendingSave()
            await configuration.waitForPendingWrites()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// Hide on a real app switch, but not during the transient resign-active
    /// event caused by opening one of Shade's own windows.
    @objc private func appDidResignActive() {
        guard configuration.load().hideOnFocusLoss, panel.isVisible else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, !NSApp.isActive, self.panel.isVisible else { return }
            self.panel.hide()
        }
    }
}

extension AppDelegate: ApplicationMenuActions {
    func applicationMenuShowAbout() {
        prepareForAuxiliaryWindow()
        about.present()
    }

    func applicationMenuShowSettings() {
        presentSettings()
    }

    func applicationMenuShowDiagnostics() {
        prepareForAuxiliaryWindow()
        diagnostics.present()
    }

    func applicationMenuCutSelection() {
        keyboard.cutSelection()
    }
}
