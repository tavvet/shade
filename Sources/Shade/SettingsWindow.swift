import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI
import UserNotifications

@MainActor
final class SettingsModel: ObservableObject {
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
    @Published var notifyThresholdSeconds: Double { didSet { save() } }
    @Published var notifyOnCommandFinish: Bool {
        didSet {
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

    private var suppressOpenAtLoginWrite = false
    private var applyDebounce: Task<Void, Never>?

    init() {
        let prefs = Preferences.load()
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
        notifyThresholdSeconds = prefs.notifyThresholdSeconds
        notifyOnCommandFinish = prefs.notifyOnCommandFinish
        openAtLogin = SMAppService.mainApp.status == .enabled
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
        let store = UserDefaults.standard
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
        store.set(notifyOnCommandFinish, forKey: Preferences.Key.notifyOnCommandFinish)
        store.set(notifyThresholdSeconds, forKey: Preferences.Key.notifyThresholdSeconds)
        scheduleApply()
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
            NotificationCenter.default.post(name: .shadePreferencesChanged, object: nil)
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

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    private let fontChoices: [(label: String, value: String)] = [
        ("System Monospace", ""),
        ("Menlo", "Menlo"),
        ("Monaco", "Monaco"),
        ("SF Mono", "SF Mono"),
        ("Courier New", "Courier New"),
    ]

    var body: some View {
        Form {
            Section("Hotkey") {
                KeyboardShortcuts.Recorder("Toggle Shade", name: .toggleShade)
            }

            Section("Keyboard Shortcuts") {
                ShortcutsList()
            }

            Section("Size") {
                fractionRow(title: "Width", value: $model.widthFraction)
                fractionRow(title: "Height", value: $model.heightFraction)
            }

            Section("Position") {
                Picker("Horizontal", selection: $model.horizontalAlignment) {
                    Text("Left").tag(Preferences.HorizontalAlignment.left)
                    Text("Center").tag(Preferences.HorizontalAlignment.center)
                    Text("Right").tag(Preferences.HorizontalAlignment.right)
                }
                .pickerStyle(.segmented)

                Picker("Screen", selection: $model.screenChoice) {
                    Text("Main").tag(Preferences.ScreenChoice.main)
                    Text("Under mouse").tag(Preferences.ScreenChoice.mouseLocation)
                }
                .pickerStyle(.segmented)
            }

            Section("Behavior") {
                Toggle("Hide when Shade loses focus", isOn: $model.hideOnFocusLoss)
                Toggle("New tab opens in the current directory", isOn: $model.newTabInheritsCwd)
                Toggle("Visual bell (flash on bell)", isOn: $model.visualBell)
            }

            Section("Appearance") {
                Picker("Font", selection: $model.fontName) {
                    ForEach(fontChoices, id: \.value) { choice in
                        Text(choice.label).tag(choice.value)
                    }
                }

                HStack {
                    Text("Size")
                        .frame(width: 76, alignment: .leading)
                    Slider(value: $model.fontSize, in: 9...22, step: 1)
                    Text("\(Int(model.fontSize)) pt")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Opacity")
                        .frame(width: 76, alignment: .leading)
                    Slider(value: $model.backgroundOpacity, in: 0.3...1.0, step: 0.05)
                    Text("\(Int((model.backgroundOpacity * 100).rounded()))%")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                        .foregroundStyle(.secondary)
                }

                ColorPicker("Link highlight", selection: $model.linkHighlightColor, supportsOpacity: false)

                Toggle("Background blur", isOn: $model.backgroundBlur)
                if model.backgroundBlur {
                    Picker("Blur material", selection: $model.blurMaterial) {
                        Text("HUD").tag(Preferences.BlurMaterial.hud)
                        Text("Under window").tag(Preferences.BlurMaterial.underWindow)
                        Text("Sidebar").tag(Preferences.BlurMaterial.sidebar)
                        Text("Full screen").tag(Preferences.BlurMaterial.fullScreen)
                    }
                }

                Picker("Cursor", selection: $model.cursorShape) {
                    Text("Block").tag(Preferences.CursorShape.block)
                    Text("Bar").tag(Preferences.CursorShape.bar)
                    Text("Underline").tag(Preferences.CursorShape.underline)
                }
                Toggle("Blink cursor", isOn: $model.cursorBlink)
            }

            Section("Startup") {
                Toggle("Open at Login", isOn: $model.openAtLogin)
            }

            Section("Notifications") {
                Toggle("Notify when a command finishes while hidden", isOn: $model.notifyOnCommandFinish)
                if model.notifyOnCommandFinish {
                    HStack {
                        Text("After")
                            .frame(width: 76, alignment: .leading)
                        Slider(value: $model.notifyThresholdSeconds, in: 5...300, step: 5)
                        Text("\(Int(model.notifyThresholdSeconds)) s")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                            .foregroundStyle(.secondary)
                    }
                    Text("Requires the OSC 133 shell snippet (see README).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Animation") {
                HStack {
                    Text("Slide")
                        .frame(width: 76, alignment: .leading)
                    Slider(value: $model.animationDuration, in: 0.0...0.5, step: 0.02)
                    Text("\(Int((model.animationDuration * 1000).rounded())) ms")
                        .monospacedDigit()
                        .frame(width: 56, alignment: .trailing)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 540, minHeight: 540)
    }

    private struct ShortcutsList: View {
        private struct Row: Identifiable {
            let id = UUID()
            let action: String
            let keys: String
        }

        private let rows: [Row] = [
            .init(action: "Toggle panel",       keys: "set above (default F12)"),
            .init(action: "Hide panel",         keys: "Esc"),
            .init(action: "New tab",            keys: "⌘T"),
            .init(action: "Close tab",          keys: "⌘W"),
            .init(action: "Switch to tab N",    keys: "⌘1 – ⌘9"),
            .init(action: "Next tab",           keys: "⌃Tab"),
            .init(action: "Previous tab",       keys: "⌃⇧Tab"),
            .init(action: "Copy / Paste",       keys: "⌘C / ⌘V"),
            .init(action: "Cut from input",     keys: "⌘X (best-effort, see README)"),
            .init(action: "Select all",         keys: "⌘A"),
            .init(action: "Clear (prompt → bottom)", keys: "⌘K"),
            .init(action: "Delete word back",   keys: "⌥⌫"),
            .init(action: "Beginning / end of line", keys: "Home / End"),
            .init(action: "Extend selection",   keys: "⇧← ⇧→ ⇧↑ ⇧↓"),
            .init(action: "  by word",          keys: "⌥⇧← / ⌥⇧→"),
            .init(action: "  to line edges",    keys: "⌘⇧← / ⌘⇧→"),
            .init(action: "Open link / file",   keys: "⌘-click"),
            .init(action: "Settings",           keys: "⌘,"),
            .init(action: "Quit",               keys: "⌘Q"),
        ]

        var body: some View {
            VStack(spacing: 4) {
                ForEach(rows) { row in
                    HStack {
                        Text(row.action)
                        Spacer()
                        Text(row.keys)
                            .foregroundStyle(.secondary)
                            .monospaced()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func fractionRow(title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
                .frame(width: 76, alignment: .leading)
            Slider(value: value, in: 0.1...1.0, step: 0.05)
            Text("\(Int((value.wrappedValue * 100).rounded()))%")
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
    }
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let model = SettingsModel()

    init() {
        let hosting = NSHostingController(rootView: SettingsView(model: model))
        hosting.preferredContentSize = NSSize(width: 580, height: 580)
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .resizable]
        window.title = "Shade Settings"
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 580, height: 580))
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("SettingsWindowController is not Storyboard-loadable") }

    func present() {
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
