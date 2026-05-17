import AppKit
import KeyboardShortcuts

@main
enum ShadeApp {
    static func main() {
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
    private lazy var panel = DropdownPanel()
    private let terminal = TerminalSession()
    private lazy var settings = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        installStatusItem()
        installTerminal()
        primePanelFrame()    // give the terminal its real rows count before starting the shell
        terminal.start()
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

    /// Lay out the panel off-screen so the terminal view computes its rows/cols.
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
        terminal.apply(prefs)
        panel.apply(prefs)
    }

    private func installTerminal() {
        let container = NSView()
        container.addSubview(terminal.view)
        NSLayoutConstraint.activate([
            terminal.view.topAnchor.constraint(equalTo: container.topAnchor),
            terminal.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            terminal.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            terminal.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        panel.contentView = container
    }

    private func toggle() {
        panel.toggle()
        if panel.isVisible {
            panel.makeFirstResponder(terminal.view)
        }
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
