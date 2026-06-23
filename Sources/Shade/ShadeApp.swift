import AppKit
import KeyboardShortcuts
import SwiftTerm
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
    private var blurView: NSVisualEffectView?
    private let commandNotifier = CommandNotifier()
    private lazy var panel: DropdownPanel = {
        let p = DropdownPanel()
        p.keyHandler = self
        p.onBecomeKey = { [weak self] in
            // Re-anchor first responder on the active terminal view every time the
            // panel becomes key — covers focus loss after switching apps or after
            // showing/hiding the panel mid-activation.
            guard let self, let active = self.terminals.activeSession else { return }
            self.panel.makeFirstResponder(active.view)
            // Refresh-after-focus-return: the user may have changed git state
            // from another tool while we were hidden. Weak reason — coordinator
            // suppresses it if we just refreshed.
            active.focusReturned()
        }
        // Pause the per-second context poll whenever the panel is off-screen; a
        // hidden drop-down shouldn't do background cwd / git / process work.
        p.onShow = { [weak self] in self?.terminals.resumePolling() }
        p.onHide = { [weak self] in self?.terminals.pausePolling() }
        return p
    }()
    private let terminals = TerminalsController()
    private lazy var tabsObservable = TabsObservable(controller: terminals)
    private lazy var settings = SettingsWindowController()
    private lazy var about = AboutWindowController()
    private lazy var diagnostics = DiagnosticsWindowController(terminals: terminals)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // macOS auto-installs "Show Tab Bar" / "Merge All Windows" key
        // equivalents (⌘T / ⌘⇧T) on any app that has an NSWindow.
        // Those bindings live above our panelHandleKey and would consume
        // ⌘T before our new-tab handler sees it. Shade has its own tab
        // model (the bottom tab bar), so the system feature is irrelevant.
        NSWindow.allowsAutomaticWindowTabbing = false

        installMainMenu()
        installStatusItem()
        installTerminals()
        installNotifications()
        primePanelFrame()
        terminals.ensureAtLeastOneSession()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyPreferences),
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
            self?.toggle()
        }
    }

    /// macOS routes ⌘C/⌘V/⌘X/⌘A through whatever menu items declare those key
    /// equivalents. Without an Edit menu the terminal view never sees them.
    /// LSUIElement apps don't show the menu bar visually, but the dispatch
    /// machinery still works as long as `NSApp.mainMenu` is set.
    private func installMainMenu() {
        let main = NSMenu()

        // App menu (slot 0 is mandatory; macOS pulls the app name from here).
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Shade")
        appMenu.addItem(withTitle: "About Shade", action: #selector(showAbout), keyEquivalent: "")
            .target = self
        appMenu.addItem(.separator())
        let settingsItem = appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Diagnostics…", action: #selector(showDiagnostics), keyEquivalent: "")
            .target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Shade",
                        action: #selector(NSApplication.hide(_:)),
                        keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Shade",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        // Edit menu — needed so ⌘C/V/X/A reach the responder chain.
        // Cut is targeted at AppDelegate directly: SwiftTerm's cut(_:) is an
        // empty stub (the buffer is read-only), and routing ⌘X through it
        // would consume the key equivalent before our keyHandler could
        // promote it to "copy if there's a selection."
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        let cutItem = editMenu.addItem(withTitle: "Cut",
                                       action: #selector(shadeCut),
                                       keyEquivalent: "x")
        cutItem.target = self
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

    /// Lay out the panel off-screen so each new terminal view computes its rows/cols.
    /// Without this the shell starts in a default 24-row buffer and the prompt
    /// ends up far from the actual bottom of the panel.
    private func primePanelFrame() {
        let prefs = Preferences.load()
        guard let screen = prefs.resolvedScreen() else { return }
        panel.setFrame(prefs.dropdownFrame(on: screen), display: false)
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    /// Adjusts the terminal font size by `delta` points (or resets to the
    /// default when `delta` is nil), persists it, and re-applies live to every
    /// session through the standard preferences-changed path.
    private func adjustFontSize(by delta: CGFloat?) {
        let store = UserDefaults.standard
        let current = Preferences.load(from: store).fontSize
        let target = Preferences.zoomedFontSize(from: current, delta: delta)
        guard target != current else { return }
        store.set(target, forKey: Preferences.Key.fontSize)
        NotificationCenter.default.post(name: .shadePreferencesChanged, object: nil)
    }

    @objc private func applyPreferences() {
        let prefs = Preferences.load()
        terminals.applyToAll(prefs)
        panel.apply(prefs)
        blurView?.isHidden = !prefs.backgroundBlur
        blurView?.material = prefs.blurMaterial.nsMaterial
    }

    /// Switching to another app hides the panel when the user opted in. Re-check
    /// on the next runloop: opening Shade's own Settings flips the activation
    /// policy, which can momentarily fire resign-active even though the app
    /// reactivates immediately. A real switch to another app leaves us inactive,
    /// so only then do we hide.
    @objc private func appDidResignActive() {
        guard Preferences.load().hideOnFocusLoss, panel.isVisible else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, !NSApp.isActive, self.panel.isVisible else { return }
            self.panel.hide()
        }
    }

    private func installNotifications() {
        commandNotifier.start()
        commandNotifier.onActivate = { [weak self] in self?.panel.show() }
        terminals.commandFinishHandler = { [weak self] duration, exitCode, cwd in
            self?.handleCommandFinish(duration: duration, exitCode: exitCode, cwd: cwd)
        }
    }

    /// A command finished in some tab. Notify only when the panel is hidden
    /// (you're looking elsewhere) and it ran long enough to be worth a ping.
    private func handleCommandFinish(duration: TimeInterval, exitCode: Int?, cwd: String) {
        guard !panel.isVisible else { return }
        let prefs = Preferences.load()
        guard prefs.notifyOnCommandFinish, duration >= prefs.notifyThresholdSeconds else { return }
        commandNotifier.post(exitCode: exitCode, duration: duration, cwd: cwd)
    }

    /// Returns keyboard focus to the active terminal — e.g. after an inline tab
    /// rename, whose text field stole first responder.
    private func focusActiveTerminal() {
        guard let view = terminals.activeSession?.view else { return }
        terminals.containerView.window?.makeFirstResponder(view)
    }

    private func installTerminals() {
        let tabBar = TabBarView(
            tabs: tabsObservable,
            onSelect: { [weak self] in self?.terminals.select(at: $0) },
            onClose: { [weak self] in self?.terminals.close(at: $0) },
            onNew: { [weak self] in self?.terminals.newSession() },
            onRename: { [weak self] index, name in self?.terminals.renameSession(at: index, to: name) },
            onEditEnd: { [weak self] in self?.focusActiveTerminal() }
        )
        let tabBarHost = NSHostingView(rootView: tabBar)
        tabBarHost.translatesAutoresizingMaskIntoConstraints = false

        // Floating git-branch badge above the terminal area.
        let badgeHost = NSHostingView(rootView: BranchBadgeView(tabs: tabsObservable))
        badgeHost.translatesAutoresizingMaskIntoConstraints = false

        // Container that overlays the badge on top of the active terminal view.
        let terminalOverlay = NSView()
        terminalOverlay.translatesAutoresizingMaskIntoConstraints = false
        terminalOverlay.addSubview(terminals.containerView)
        terminalOverlay.addSubview(badgeHost)
        NSLayoutConstraint.activate([
            terminals.containerView.topAnchor.constraint(equalTo: terminalOverlay.topAnchor),
            terminals.containerView.bottomAnchor.constraint(equalTo: terminalOverlay.bottomAnchor),
            terminals.containerView.leadingAnchor.constraint(equalTo: terminalOverlay.leadingAnchor),
            terminals.containerView.trailingAnchor.constraint(equalTo: terminalOverlay.trailingAnchor),
            badgeHost.topAnchor.constraint(equalTo: terminalOverlay.topAnchor),
            badgeHost.trailingAnchor.constraint(equalTo: terminalOverlay.trailingAnchor),
        ])

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 0
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(terminalOverlay)
        stack.addArrangedSubview(tabBarHost)

        NSLayoutConstraint.activate([
            tabBarHost.heightAnchor.constraint(equalToConstant: 28),
            tabBarHost.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            tabBarHost.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            terminalOverlay.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            terminalOverlay.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
        ])

        // Frosted-glass backdrop. The terminal paints its own background with the
        // user's opacity, so wherever that alpha < 1 this blur of the content
        // behind the window shows through instead of raw passthrough. It sits at
        // the back of the panel; visibility is toggled live in applyPreferences.
        let blurPrefs = Preferences.load()
        let blur = NSVisualEffectView()
        blur.material = blurPrefs.blurMaterial.nsMaterial
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.appearance = NSAppearance(named: .darkAqua)
        blur.translatesAutoresizingMaskIntoConstraints = false
        blur.isHidden = !blurPrefs.backgroundBlur
        blurView = blur

        let root = NSView()
        root.addSubview(blur)
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            blur.topAnchor.constraint(equalTo: root.topAnchor),
            blur.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            blur.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        ])

        panel.contentView = root
    }

    private func toggle() {
        // Focus is restored by panel.onBecomeKey whenever the panel actually
        // becomes the key window, so toggle() only has to flip the panel.
        panel.toggle()
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let url = Bundle.main.url(forResource: "MenubarIcon", withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                image.size = NSSize(width: 18, height: 18)
                image.isTemplate = false   // icon is intentionally colored
                button.image = image
            } else {
                button.title = "▾"
            }
            button.toolTip = "Shade"
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "About Shade", action: #selector(showAbout), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Diagnostics…", action: #selector(showDiagnostics), keyEquivalent: "")
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

    @objc private func showAbout() {
        about.present()
    }

    @objc private func showDiagnostics() {
        diagnostics.present()
    }

    /// Wired to Edit → Cut.
    ///
    /// The terminal buffer itself is read-only — Shade can't surgically
    /// remove a range of cells. What it *can* do is poke backspaces into
    /// the shell's PTY: readline removes chars to the left of its cursor.
    /// So ⌘X copies the selected text and then sends N DEL bytes, which
    /// behaves the same as `clear-line` for the common case (selection
    /// runs from cursor backward via ⇧← / ⌥⇧←). For mid-line or
    /// multi-line selections it'll still delete N chars *from the
    /// cursor*, not from the highlighted region — there's no way to
    /// reposition readline from the outside reliably.
    @objc private func shadeCut() {
        guard let view = terminals.activeSession?.view,
              let text = view.shadeSelectedText() else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        let backspaces = [UInt8](repeating: 0x7F, count: text.count)
        view.send(backspaces)
        view.clearKeyboardSelection()
    }
}

extension AppDelegate: PanelKeyHandler {
    /// Tab shortcuts follow the macOS convention used by iTerm2/Terminal/Safari/Chrome.
    /// ⌘-keys are safe — shell uses ⌃-combinations.
    ///
    /// Letter dispatch goes through `KeyCodes.asciiLetterForKeyCode` (physical
    /// QWERTY position), not `charactersIgnoringModifiers`. macOS only does
    /// the Command-key-to-QWERTY fallback inside `NSMenuItem.keyEquivalent`
    /// matching; raw event inspection here would otherwise see "ц" / "е" / …
    /// on a Cyrillic input source and fail the equality check.
    func panelHandleKey(_ event: NSEvent) -> Bool {
        let userKeys: NSEvent.ModifierFlags = [.shift, .control, .option, .command]
        let flags = event.modifierFlags.intersection(userKeys)
        let cmd: NSEvent.ModifierFlags = [.command]
        let ctrl: NSEvent.ModifierFlags = [.control]
        let ctrlShift: NSEvent.ModifierFlags = [.control, .shift]
        let chars = event.charactersIgnoringModifiers ?? ""
        let letter = KeyCodes.asciiLetterForKeyCode[event.keyCode]

        // Tab key has its own keyCode (kVK_Tab); `chars` is `\t`.
        let isTab = event.keyCode == KeyCodes.tab

        // Font zoom: ⌘= / ⌘+ bigger, ⌘− smaller, ⌘0 reset. Matched by physical
        // keyCode so it's layout-agnostic; ⌘+ arrives as ⌘⇧=, so the zoom-in
        // key also accepts Shift.
        if event.keyCode == KeyCodes.equal, flags == cmd || flags == [.command, .shift] {
            adjustFontSize(by: 1)
            return true
        }
        if flags == cmd, event.keyCode == KeyCodes.minus {
            adjustFontSize(by: -1)
            return true
        }
        if flags == cmd, event.keyCode == KeyCodes.zero {
            adjustFontSize(by: nil)
            return true
        }

        if flags == cmd {
            switch letter {
            case "t":
                terminals.newSession()
                return true
            case "w":
                terminals.closeActive()
                return true
            case "k":
                // Guake-style clear: erase the visible screen and put the
                // cursor at the bottom row so the next prompt lands there
                // (the builtin `clear` puts the cursor at row 0 → prompt at
                // the top, which feels wrong in a drop-down).
                clearVisibleScreen()
                return true
            // ⌘X is routed via the Edit menu's shadeCut item (see installMainMenu);
            // we don't intercept it here because the main-menu dispatch wins
            // before performKeyEquivalent is consulted on the window.
            default:
                // The digit row produces the same characters on every layout,
                // so `chars` is fine for ⌘1…⌘9.
                if let digit = Int(chars), (1...9).contains(digit) {
                    // Only consume the event when the index actually exists, otherwise
                    // the keystroke silently disappears (e.g. ⌘5 with only 3 tabs).
                    let target = digit - 1
                    if terminals.sessions.indices.contains(target) {
                        terminals.select(at: target)
                        return true
                    }
                    return false
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

        // OSC 133 prompt navigation. Arrow keys on macOS carry .function and
        // .numericPad in their modifierFlags on top of the user-held keys, so
        // we compare against a user-only mask (the same trick DropdownPanel's
        // keyboardSelectionAction uses for ⌘⇧← / ⌘⇧→). Letter & arrow keys
        // are both matched by physical keyCode — `charactersIgnoringModifiers`
        // would return Cyrillic / Greek / etc on non-Latin layouts.
        let cmdShiftOnly: NSEvent.ModifierFlags = [.command, .shift]
        if flags == cmdShiftOnly {
            switch event.keyCode {
            case KeyCodes.upArrow:
                // Always consume: if there's no prompt mark to jump to we
                // still don't want the event leaking into SwiftTerm, where
                // AppKit's default `moveToBeginningOfDocumentAndModifySelection`
                // would extend the selection over the whole buffer (looks
                // like an opacity change on the translucent background).
                terminals.activeSession?.jumpToPreviousPrompt()
                return true
            case KeyCodes.downArrow:
                terminals.activeSession?.jumpToNextPrompt()
                return true
            default:
                if letter == "o" {
                    terminals.activeSession?.copyLastCommandOutput()
                    return true
                }
            }
        }

        return false
    }

    func panelSendToActiveTerminal(_ bytes: [UInt8]) {
        terminals.activeSession?.view.send(bytes)
    }

    func panelExtendKeyboardSelection(direction: TerminalView.ShadeKeyboardDirection, byWord: Bool) {
        terminals.activeSession?.view.extendKeyboardSelection(direction: direction, byWord: byWord)
    }

    /// Guake-style clear: erase the visible grid and park the cursor at the bottom row,
    /// then prompt the shell to redraw at its new (now bottom) cursor position.
    ///
    /// The CSI sequence goes through `view.feed(text:)` — that path drops the bytes
    /// straight into the terminal emulator the way the *shell* would write them.
    /// If we used `view.send(...)` instead, the bytes would land in the shell's
    /// stdin and zsh would happily try to execute `3;1H` as a command.
    /// Then a single CR on the input side asks the shell to redraw its prompt at
    /// the freshly-moved cursor.
    private func clearVisibleScreen() {
        guard let session = terminals.activeSession else { return }
        let rows = session.view.getTerminal().rows
        let lastRow = max(1, rows)
        let escape = "\u{1B}[2J\u{1B}[\(lastRow);1H"
        session.view.feed(text: escape)
        session.view.send([0x0D])
    }
}
