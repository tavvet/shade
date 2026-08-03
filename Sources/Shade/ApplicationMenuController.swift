import AppKit

@MainActor
protocol ApplicationMenuActions: AnyObject {
    func applicationMenuShowAbout()
    func applicationMenuShowSettings()
    func applicationMenuShowDiagnostics()
    func applicationMenuCutSelection()
}

/// Owns Shade's main menu and menu-bar status item.
///
/// Keeping their selector targets here prevents AppDelegate from becoming the
/// catch-all owner for every application command.
@MainActor
final class ApplicationMenuController: NSObject {
    weak var actions: ApplicationMenuActions?

    private var statusItem: NSStatusItem?

    init(actions: ApplicationMenuActions? = nil) {
        self.actions = actions
        super.init()
    }

    func install() {
        installMainMenu()
        installStatusItem()
    }

    /// macOS routes ⌘C/⌘V/⌘X/⌘A through menu items declaring those
    /// key equivalents. LSUIElement apps do not show this menu visually, but the
    /// responder-chain dispatch still requires `NSApp.mainMenu`.
    private func installMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Shade")
        addActionItem(to: appMenu, title: "About Shade", action: #selector(showAbout))
        appMenu.addItem(.separator())
        addActionItem(to: appMenu, title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        addActionItem(to: appMenu, title: "Diagnostics…", action: #selector(showDiagnostics))
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Shade",
                        action: #selector(NSApplication.hide(_:)),
                        keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Shade",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        // SwiftTerm's cut(_:) is an empty stub. Route ⌘X to Shade so the
        // selection can be copied before backspaces are sent to the shell.
        addActionItem(to: editMenu, title: "Cut", action: #selector(cutSelection), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy",
                         action: #selector(NSText.copy(_:)),
                         keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste",
                         action: #selector(NSText.paste(_:)),
                         keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All",
                         action: #selector(NSResponder.selectAll(_:)),
                         keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        NSApp.mainMenu = main
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let url = Bundle.main.url(forResource: "MenubarIcon", withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                image.size = NSSize(width: 18, height: 18)
                image.isTemplate = false
                button.image = image
            } else {
                button.title = "▾"
            }
            button.toolTip = "Shade"
        }

        let menu = NSMenu()
        addActionItem(to: menu, title: "About Shade", action: #selector(showAbout))
        menu.addItem(.separator())
        addActionItem(to: menu, title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        addActionItem(to: menu, title: "Diagnostics…", action: #selector(showDiagnostics))
        menu.addItem(.separator())
        addActionItem(to: menu, title: "Quit Shade", action: #selector(quit), keyEquivalent: "q")
        item.menu = menu

        statusItem = item
    }

    @discardableResult
    private func addActionItem(
        to menu: NSMenu,
        title: String,
        action: Selector,
        keyEquivalent: String = ""
    ) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    @objc private func showAbout() {
        actions?.applicationMenuShowAbout()
    }

    @objc private func showSettings() {
        actions?.applicationMenuShowSettings()
    }

    @objc private func showDiagnostics() {
        actions?.applicationMenuShowDiagnostics()
    }

    @objc private func cutSelection() {
        actions?.applicationMenuCutSelection()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
