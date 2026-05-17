import AppKit

/// Borderless, non-activating panel that slides down from the top of the screen.
@MainActor
final class DropdownPanel: NSPanel {
    private let slideDuration: TimeInterval = 0.16

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = NSColor(white: 0.08, alpha: 0.94)
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        animationBehavior = .none
    }

    // NSPanel with .borderless refuses key status by default.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Esc hides the panel. Other keys pass through to the content view (the terminal, later).
    override func cancelOperation(_ sender: Any?) {
        hide()
    }

    override func animationResizeTime(_ newWindow: NSRect) -> TimeInterval {
        slideDuration
    }

    // MARK: - Show / hide with slide animation

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        let prefs = Preferences.load()
        guard let screen = prefs.resolvedScreen() else { return }
        let finalFrame = prefs.dropdownFrame(on: screen)
        let hiddenFrame = NSRect(x: finalFrame.minX,
                                 y: finalFrame.maxY,
                                 width: finalFrame.width,
                                 height: 0)

        setFrame(hiddenFrame, display: false)
        orderFrontRegardless()
        makeKey()
        NSApp.activate(ignoringOtherApps: true)
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
