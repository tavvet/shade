import AppKit

/// Borderless, non-activating panel that slides down from the top of the screen.
@MainActor
final class DropdownPanel: NSPanel {
    private var slideDuration: TimeInterval = Preferences.defaults.animationDuration

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        animationBehavior = .none
        apply(Preferences.load())
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        hide()
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
