import AppKit
import SwiftTerm

/// Applies user appearance preferences and transient visual effects to a
/// SwiftTerm view without making the session coordinator own rendering details.
@MainActor
enum TerminalAppearance {
    static func apply(_ prefs: Preferences, to view: LocalProcessTerminalView) {
        view.font = prefs.terminalFont()
        view.nativeBackgroundColor = NSColor(white: 0.08, alpha: prefs.backgroundOpacity)
        view.linkHoverColor = prefs.linkHighlightColor()
        view.wantsLayer = true
        view.layer?.isOpaque = false
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.feed(text: prefs.cursorDECSCUSR)
    }

    @discardableResult
    static func flashBell(in view: LocalProcessTerminalView) -> Bool {
        guard Preferences.load().visualBell else { return false }
        let flash = NSView(frame: view.bounds)
        flash.autoresizingMask = [.width, .height]
        flash.wantsLayer = true
        flash.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.22).cgColor
        view.addSubview(flash)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            flash.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { flash.removeFromSuperview() }
        })
        return true
    }
}
