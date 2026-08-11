import AppKit
import ServiceManagement
import SwiftUI
import UserNotifications

@MainActor
final class SettingsModel: NSObject, ObservableObject {
    @Published var widthFraction: Double          { didSet { save() } }
    @Published var heightFraction: Double         { didSet { save() } }
    @Published var horizontalAlignment: Preferences.HorizontalAlignment { didSet { save() } }
    @Published var screenChoice: Preferences.ScreenChoice               { didSet { save() } }
    @Published var fontSize: Double               { didSet { save() } }
    @Published var fontName: String               { didSet { save() } }
    @Published var backgroundOpacity: Double      { didSet { save() } }
    @Published var animationDuration: Double      { didSet { save() } }
    @Published var linkHighlightColor: Color      { didSet { save() } }
    @Published var backgroundBlur: Bool           { didSet { save() } }
    @Published var blurMaterial: Preferences.BlurMaterial { didSet { save() } }
    @Published var cursorShape: Preferences.CursorShape { didSet { save() } }
    @Published var cursorBlink: Bool              { didSet { save() } }
    @Published var visualBell: Bool               { didSet { save() } }
    @Published var hideOnFocusLoss: Bool          { didSet { save() } }
    @Published var newTabInheritsCwd: Bool        { didSet { save() } }
    @Published var shellEnrichment: Bool          { didSet { save() } }
    @Published var notifyThresholdSeconds: Double { didSet { save() } }
    @Published var notifyOnCommandFinish: Bool {
        didSet {
            guard !suppressPreferenceWrites else { return }
            save()
            if notifyOnCommandFinish, !oldValue {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
            }
        }
    }
    @Published var openAtLogin: Bool {
        didSet {
            guard oldValue != openAtLogin, !suppressOpenAtLoginWrite else { return }
            applyOpenAtLogin()
        }
    }

    private let store: UserDefaults
    private var suppressPreferenceWrites = false
    private var suppressOpenAtLoginWrite = false
    private var applyDebounce: Task<Void, Never>?

    init(store: UserDefaults = .standard, openAtLogin: Bool? = nil) {
        self.store = store
        let prefs = Preferences.load(from: store)
        widthFraction = Double(prefs.widthFraction)
        heightFraction = Double(prefs.heightFraction)
        horizontalAlignment = prefs.horizontalAlignment
        screenChoice = prefs.screenChoice
        fontSize = Double(prefs.fontSize)
        fontName = prefs.fontName
        backgroundOpacity = prefs.backgroundOpacity
        animationDuration = prefs.animationDuration
        linkHighlightColor = Color(nsColor: prefs.linkHighlightColor())
        backgroundBlur = prefs.backgroundBlur
        blurMaterial = prefs.blurMaterial
        cursorShape = prefs.cursorShape
        cursorBlink = prefs.cursorBlink
        visualBell = prefs.visualBell
        hideOnFocusLoss = prefs.hideOnFocusLoss
        newTabInheritsCwd = prefs.newTabInheritsCwd
        shellEnrichment = prefs.shellEnrichment
        notifyThresholdSeconds = prefs.notifyThresholdSeconds
        notifyOnCommandFinish = prefs.notifyOnCommandFinish
        self.openAtLogin = openAtLogin ?? (SMAppService.mainApp.status == .enabled)
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

    private func applyOpenAtLogin() {
        do {
            if openAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Shade: open-at-login change failed: %@", String(describing: error))
            // Revert the toggle without re-firing didSet.
            suppressOpenAtLoginWrite = true
            openAtLogin = SMAppService.mainApp.status == .enabled
            suppressOpenAtLoginWrite = false
        }
    }

    private func save() {
        guard !suppressPreferenceWrites else { return }
        store.set(widthFraction, forKey: Preferences.Key.widthFraction)
        store.set(heightFraction, forKey: Preferences.Key.heightFraction)
        store.set(horizontalAlignment.rawValue, forKey: Preferences.Key.horizontalAlignment)
        store.set(screenChoice.rawValue, forKey: Preferences.Key.screenChoice)
        store.set(fontSize, forKey: Preferences.Key.fontSize)
        store.set(fontName, forKey: Preferences.Key.fontName)
        store.set(backgroundOpacity, forKey: Preferences.Key.backgroundOpacity)
        store.set(animationDuration, forKey: Preferences.Key.animationDuration)
        store.set(Self.hexString(from: linkHighlightColor), forKey: Preferences.Key.linkHighlightHex)
        store.set(backgroundBlur, forKey: Preferences.Key.backgroundBlur)
        store.set(blurMaterial.rawValue, forKey: Preferences.Key.blurMaterial)
        store.set(cursorShape.rawValue, forKey: Preferences.Key.cursorShape)
        store.set(cursorBlink, forKey: Preferences.Key.cursorBlink)
        store.set(visualBell, forKey: Preferences.Key.visualBell)
        store.set(hideOnFocusLoss, forKey: Preferences.Key.hideOnFocusLoss)
        store.set(newTabInheritsCwd, forKey: Preferences.Key.newTabInheritsCwd)
        store.set(shellEnrichment, forKey: Preferences.Key.shellEnrichment)
        store.set(notifyOnCommandFinish, forKey: Preferences.Key.notifyOnCommandFinish)
        store.set(notifyThresholdSeconds, forKey: Preferences.Key.notifyThresholdSeconds)
        scheduleApply()
    }

    /// Re-read values changed outside this model, such as keyboard font zoom or
    /// `defaults write`, without echoing every assignment back to UserDefaults.
    func reloadPreferences() {
        let prefs = Preferences.load(from: store)
        suppressPreferenceWrites = true
        defer { suppressPreferenceWrites = false }
        widthFraction = Double(prefs.widthFraction)
        heightFraction = Double(prefs.heightFraction)
        horizontalAlignment = prefs.horizontalAlignment
        screenChoice = prefs.screenChoice
        fontSize = Double(prefs.fontSize)
        fontName = prefs.fontName
        backgroundOpacity = prefs.backgroundOpacity
        animationDuration = prefs.animationDuration
        linkHighlightColor = Color(nsColor: prefs.linkHighlightColor())
        backgroundBlur = prefs.backgroundBlur
        blurMaterial = prefs.blurMaterial
        cursorShape = prefs.cursorShape
        cursorBlink = prefs.cursorBlink
        visualBell = prefs.visualBell
        hideOnFocusLoss = prefs.hideOnFocusLoss
        newTabInheritsCwd = prefs.newTabInheritsCwd
        shellEnrichment = prefs.shellEnrichment
        notifyThresholdSeconds = prefs.notifyThresholdSeconds
        notifyOnCommandFinish = prefs.notifyOnCommandFinish
    }

    @objc private func preferencesChanged(_ notification: Notification) {
        if let source = notification.object as AnyObject?, source === self { return }
        reloadPreferences()
    }

    /// Coalesce the live re-apply. A slider / color-picker drag fires `save()`
    /// on every tick, and re-applying font/opacity to every terminal session is
    /// the expensive part (SwiftTerm relayouts on each font change). The writes
    /// above are cheap and stay immediate, so values are always persisted; only
    /// the notification — and thus the re-apply — waits for a brief pause.
    private func scheduleApply() {
        applyDebounce?.cancel()
        applyDebounce = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            NotificationCenter.default.post(name: .shadePreferencesChanged, object: self)
        }
    }

    private static func hexString(from color: Color) -> String {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        let r = Int(round(ns.redComponent * 255))
        let g = Int(round(ns.greenComponent * 255))
        let b = Int(round(ns.blueComponent * 255))
        return String(format: "%02X%02X%02X", r, g, b)
    }
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let model = SettingsModel()

    init() {
        let hosting = NSHostingController(rootView: SettingsView(model: model))
        hosting.preferredContentSize = NSSize(width: 800, height: 580)
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .resizable]
        window.title = "Shade Settings"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 720, height: 500)
        window.setContentSize(NSSize(width: 800, height: 580))
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("SettingsWindowController is not Storyboard-loadable") }

    func present() {
        model.reloadPreferences()
        // Switch from .accessory to .regular while the Settings window is open so that
        // system panels (notably NSColorPanel used by SwiftUI's ColorPicker) actually
        // open — they refuse to show for LSUIElement / .accessory apps.
        NSApp.setActivationPolicy(.regular)
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        positionColorPanelNearSettings()
    }

    /// Without nudging it, NSColorPanel opens in the bottom-left of the active screen
    /// the first time it's used. Position it next to the Settings window instead.
    private func positionColorPanelNearSettings() {
        let panel = NSColorPanel.shared   // touching `.shared` creates the panel if needed
        guard let settingsFrame = window?.frame, let screen = NSScreen.main else {
            panel.center()
            return
        }
        let panelSize = panel.frame.size
        var origin = NSPoint(
            x: settingsFrame.maxX + 20,
            y: settingsFrame.midY - panelSize.height / 2
        )
        // If we'd overflow the right edge of the visible screen, fall back to the left.
        let visible = screen.visibleFrame
        if origin.x + panelSize.width > visible.maxX {
            origin.x = max(visible.minX, settingsFrame.minX - panelSize.width - 20)
        }
        // Keep within vertical bounds too.
        origin.y = min(max(origin.y, visible.minY), visible.maxY - panelSize.height)
        panel.setFrameOrigin(origin)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
