import AppKit
import KeyboardShortcuts
import SwiftUI

@main
enum ShadeApp {
    static func main() {
        // GUI apps launched via LaunchServices start with cwd = "/", which then
        // becomes the starting directory for every spawned shell. Push us to $HOME
        // so new tabs open there by default.
        FileManager.default.changeCurrentDirectoryPath(NSHomeDirectory())

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private lazy var panel: DropdownPanel = {
        let p = DropdownPanel()
        p.keyHandler = self
        return p
    }()
    private let terminals = TerminalsController()
    private lazy var tabsObservable = TabsObservable(controller: terminals)
    private lazy var settings = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        installStatusItem()
        installTerminals()
        primePanelFrame()
        terminals.ensureAtLeastOneSession()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyPreferences),
            name: .shadePreferencesChanged,
            object: nil
        )
        KeyboardShortcuts.onKeyDown(for: .toggleShade) { [weak self] in
            self?.toggle()
        }
    }

    /// Lay out the panel off-screen so each new terminal view computes its rows/cols.
    /// Without this the shell starts in a default 24-row buffer and the prompt
    /// ends up far from the actual bottom of the panel.
    private func primePanelFrame() {
        let prefs = Preferences.load()
        guard let screen = prefs.resolvedScreen() else { return }
        panel.setFrame(prefs.dropdownFrame(on: screen), display: false)
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    @objc private func applyPreferences() {
        let prefs = Preferences.load()
        terminals.applyToAll(prefs)
        panel.apply(prefs)
    }

    private func installTerminals() {
        let tabBar = TabBarView(
            tabs: tabsObservable,
            onSelect: { [weak self] in self?.terminals.select(at: $0) },
            onClose: { [weak self] in self?.terminals.close(at: $0) },
            onNew: { [weak self] in self?.terminals.newSession() }
        )
        let tabBarHost = NSHostingView(rootView: tabBar)
        tabBarHost.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 0
        stack.distribution = .fill
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(terminals.containerView)
        stack.addArrangedSubview(tabBarHost)

        // Tab bar fixed height, terminal fills the rest, both span the full width.
        NSLayoutConstraint.activate([
            tabBarHost.heightAnchor.constraint(equalToConstant: 28),
            tabBarHost.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            tabBarHost.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            terminals.containerView.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            terminals.containerView.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
        ])

        panel.contentView = stack
    }

    private func toggle() {
        panel.toggle()
        if panel.isVisible, let view = terminals.activeSession?.view {
            panel.makeFirstResponder(view)
        }
    }

}

extension AppDelegate: PanelKeyHandler {
    /// Tab shortcuts follow the macOS convention used by iTerm2/Terminal/Safari/Chrome.
    /// ⌘-keys are safe — shell uses ⌃-combinations.
    func panelHandleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmd: NSEvent.ModifierFlags = [.command]
        let ctrl: NSEvent.ModifierFlags = [.control]
        let ctrlShift: NSEvent.ModifierFlags = [.control, .shift]
        let chars = event.charactersIgnoringModifiers ?? ""

        // Tab key has its own keyCode (48) and `chars` is `\t`.
        let isTab = event.keyCode == 48

        if flags == cmd {
            switch chars.lowercased() {
            case "t":
                terminals.newSession()
                return true
            case "w":
                terminals.closeActive()
                return true
            default:
                if let digit = Int(chars), (1...9).contains(digit) {
                    terminals.select(at: digit - 1)
                    return true
                }
            }
        }

        if isTab && flags == ctrl {
            terminals.selectNext()
            return true
        }
        if isTab && flags == ctrlShift {
            terminals.selectPrev()
            return true
        }

        return false
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.title = "▾"
            button.toolTip = "Shade"
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Shade", action: #selector(quit), keyEquivalent: "q")
            .target = self
        item.menu = menu

        statusItem = item
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func showSettings() {
        settings.present()
    }
}
