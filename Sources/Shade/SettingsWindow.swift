import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

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
    @Published var openAtLogin: Bool {
        didSet {
            guard oldValue != openAtLogin, !suppressOpenAtLoginWrite else { return }
            applyOpenAtLogin()
        }
    }

    private var suppressOpenAtLoginWrite = false

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
        NotificationCenter.default.post(name: .shadePreferencesChanged, object: nil)
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
            }

            Section("Startup") {
                Toggle("Open at Login", isOn: $model.openAtLogin)
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
            .init(action: "Copy / Paste / Cut", keys: "⌘C / ⌘V / ⌘X"),
            .init(action: "Select all",         keys: "⌘A"),
            .init(action: "Delete word back",   keys: "⌥⌫"),
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
