import AppKit

@MainActor
protocol PanelKeyHandler: AnyObject {
    /// Return true if the event was handled and should not propagate.
    func panelHandleKey(_ event: NSEvent) -> Bool
    /// Forward raw bytes to the currently active terminal session (PTY input).
    func panelSendToActiveTerminal(_ bytes: [UInt8])
}

/// Borderless panel that slides down from the top of the screen.
/// Becomes the key window when shown so keyboard shortcuts route to us.
@MainActor
final class DropdownPanel: NSPanel {
    private var slideDuration: TimeInterval = Preferences.defaults.animationDuration

    /// Set by AppDelegate to receive tab keyboard shortcuts.
    weak var keyHandler: PanelKeyHandler?

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
        if keyHandler?.panelHandleKey(event) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Intercept keyDown so we can translate Control+letter into the canonical control byte
    /// regardless of the current keyboard layout (otherwise SwiftTerm applies the control
    /// mask to whatever Cyrillic/Greek/etc character is produced, which the shell can't parse).
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           let handler = keyHandler,
           let bytes = controlBytes(for: event) {
            handler.panelSendToActiveTerminal(bytes)
            return
        }
        super.sendEvent(event)
    }

    private func controlBytes(for event: NSEvent) -> [UInt8]? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let control: NSEvent.ModifierFlags = [.control]
        let controlShift: NSEvent.ModifierFlags = [.control, .shift]
        guard flags == control || flags == controlShift else { return nil }
        guard let byte = KeyCodes.controlByte(forKeyCode: event.keyCode) else { return nil }
        return [byte]
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
        orderFrontRegardless()
        makeKey()
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        setFrame(finalFrame, display: true, animate: true)
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
    }
}
