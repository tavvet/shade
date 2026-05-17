import AppKit
import SwiftTerm

@MainActor
protocol PanelKeyHandler: AnyObject {
    /// Return true if the event was handled and should not propagate.
    func panelHandleKey(_ event: NSEvent) -> Bool
    /// Forward raw bytes to the currently active terminal session (PTY input).
    func panelSendToActiveTerminal(_ bytes: [UInt8])
    /// Extend the keyboard selection of the active session in `direction`.
    func panelExtendKeyboardSelection(direction: TerminalView.ShadeKeyboardDirection, byWord: Bool)
}

/// Borderless panel that slides down from the top of the screen.
/// Becomes the key window when shown so keyboard shortcuts route to us.
@MainActor
final class DropdownPanel: NSPanel {
    private var slideDuration: TimeInterval = Preferences.defaults.animationDuration

    /// Set by AppDelegate to receive tab keyboard shortcuts.
    weak var keyHandler: PanelKeyHandler?

    /// Fired every time the panel transitions to key window. Lets AppDelegate
    /// re-anchor first responder on the active terminal view — relying only on
    /// a one-shot makeFirstResponder right after toggle() racy when
    /// NSApp.activate hasn't fully landed yet.
    var onBecomeKey: (() -> Void)?

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
        if keyHandler?.panelHandleKey(event) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Intercept keyDown so we can:
    /// * Translate Control+letter into the canonical control byte regardless of the
    ///   current keyboard layout (otherwise SwiftTerm applies the control mask to whatever
    ///   Cyrillic/Greek/etc character is produced, which the shell can't parse).
    /// * Translate Option+Delete into the readline backward-kill-word escape (`ESC DEL`),
    ///   which Terminal.app sends by default. Other Option+key combinations are left alone
    ///   so SwiftTerm can still produce ´/©/etc.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, let handler = keyHandler {
            if let bytes = controlBytes(for: event) {
                handler.panelSendToActiveTerminal(bytes)
                return
            }
            if let bytes = optionDeleteBytes(for: event) {
                handler.panelSendToActiveTerminal(bytes)
                return
            }
            if let bytes = homeEndBytes(for: event) {
                handler.panelSendToActiveTerminal(bytes)
                return
            }
            if let (direction, byWord) = keyboardSelectionAction(for: event) {
                handler.panelExtendKeyboardSelection(direction: direction, byWord: byWord)
                return
            }
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

    /// Option+Delete → ESC DEL (readline backward-kill-word).
    private func optionDeleteBytes(for event: NSEvent) -> [UInt8]? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == [.option] else { return nil }
        // 51 = kVK_Delete (Backspace on Mac keyboards).
        guard event.keyCode == 51 else { return nil }
        return [0x1B, 0x7F]
    }

    /// Home / End → readline ⌃A / ⌃E. Stock SwiftTerm would send the function-key
    /// escape (\e[H, \e[F, or \e[1~/4~ depending on mode), which only works if
    /// the user's shell happens to bind that sequence to beginning-of-line. The
    /// raw control byte works everywhere readline (and zle, fish, etc) is alive.
    private func homeEndBytes(for event: NSEvent) -> [UInt8]? {
        let userKeys: NSEvent.ModifierFlags = [.shift, .control, .option, .command]
        let flags = event.modifierFlags.intersection(userKeys)
        guard flags.isEmpty else { return nil }    // shift+Home/End → selection (TODO)
        switch event.keyCode {
        case 115: return [0x01]   // Home → ⌃A
        case 119: return [0x05]   // End  → ⌃E
        default:  return nil
        }
    }

    /// Shift+arrow (and ⌥⇧+arrow for word jumps) drive in-buffer keyboard selection.
    /// Plain arrow keys (no modifier) are NOT intercepted here — they flow through to
    /// SwiftTerm so the shell still gets its history / cursor navigation, and the
    /// existing `selection.active = false` at the top of SwiftTerm's `keyDown` clears
    /// the selection automatically.
    private func keyboardSelectionAction(for event: NSEvent) -> (TerminalView.ShadeKeyboardDirection, Bool)? {
        // Arrow keys carry .function and .numericPad in their modifier flags on macOS;
        // mask those off so we only compare the explicit user-held modifier keys.
        let userKeys: NSEvent.ModifierFlags = [.shift, .control, .option, .command]
        let flags = event.modifierFlags.intersection(userKeys)
        let shift: NSEvent.ModifierFlags = [.shift]
        let optShift: NSEvent.ModifierFlags = [.option, .shift]
        let cmdShift: NSEvent.ModifierFlags = [.command, .shift]
        guard flags == shift || flags == optShift || flags == cmdShift else { return nil }

        let direction: TerminalView.ShadeKeyboardDirection
        switch (event.keyCode, flags == cmdShift) {
        case (123, false): direction = .left
        case (124, false): direction = .right
        case (126, false): direction = .up
        case (125, false): direction = .down
        case (123, true):  direction = .lineStart   // ⌘⇧← → select to beginning of line
        case (124, true):  direction = .lineEnd     // ⌘⇧→ → select to end of line
        default: return nil
        }
        let byWord = flags == optShift
        return (direction, byWord)
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
