import AppKit

/// Borderless panel that slides down from the top of the screen.
/// Becomes the key window when shown so keyboard shortcuts route to us.
@MainActor
final class DropdownPanel: NSPanel {
    private var slideDuration: TimeInterval = Preferences.defaults.animationDuration

    /// Receives panel-level shortcuts and terminal input forwarding.
    weak var keyHandler: PanelKeyHandler?

    /// Fired every time the panel transitions to key window. Lets the app
    /// re-anchor first responder on the active terminal view — relying only on
    /// a one-shot makeFirstResponder right after toggle() racy when
    /// NSApp.activate hasn't fully landed yet.
    var onBecomeKey: (() -> Void)?

    /// Fired when the panel slides on-screen / off-screen. The app uses these
    /// to resume / pause the per-second context poll, so a hidden panel does no
    /// background cwd / git / process work.
    var onShow: (() -> Void)?
    var onHide: (() -> Void)?

    override func becomeKey() {
        super.becomeKey()
        onBecomeKey?()
    }

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        animationBehavior = .none
        apply(Preferences.load())
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        hide()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if !PanelInputRouting.isEditingText(firstResponder),
           keyHandler?.panelHandleKey(event) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           !PanelInputRouting.isEditingText(firstResponder),
           let input = PanelTerminalInputResolver.resolve(
               keyCode: event.keyCode,
               modifierFlags: event.modifierFlags
           ),
           let handler = keyHandler {
            handler.panelHandleTerminalInput(input)
            return
        }
        super.sendEvent(event)
    }

    override func animationResizeTime(_ newWindow: NSRect) -> TimeInterval {
        slideDuration
    }

    func apply(_ prefs: Preferences) {
        slideDuration = prefs.animationDuration
        // Panel itself is transparent; the terminal view paints its own background
        // (with the user-controlled opacity) so the effect is uniform across the panel.
        backgroundColor = .clear
    }

    // MARK: - Show / hide with slide animation

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        let prefs = Preferences.load()
        apply(prefs)
        guard let screen = prefs.resolvedScreen() else { return }
        let finalFrame = prefs.dropdownFrame(on: screen)
        let hiddenFrame = NSRect(x: finalFrame.minX,
                                 y: finalFrame.maxY,
                                 width: finalFrame.width,
                                 height: 0)

        setFrame(hiddenFrame, display: false)
        // ignoringOtherApps is more aggressive than the no-arg .activate() on
        // macOS 14+ and reliably promotes an .accessory app back to active when
        // the user is returning from another application via the global hotkey.
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        setFrame(finalFrame, display: true, animate: true)
        onShow?()
    }

    func hide() {
        guard isVisible else { return }
        let current = frame
        let hiddenFrame = NSRect(x: current.minX,
                                 y: current.maxY,
                                 width: current.width,
                                 height: 0)
        setFrame(hiddenFrame, display: true, animate: true)
        orderOut(nil)
        onHide?()
    }
}
