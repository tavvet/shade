import AppKit
import SwiftTerm

/// Applies user appearance preferences and transient visual effects to a
/// SwiftTerm view without making the session coordinator own rendering details.
@MainActor
enum TerminalAppearance {
    static func apply(_ prefs: Preferences, to view: LocalProcessTerminalView) {
        view.font = prefs.terminalFont()
        view.nativeBackgroundColor = NSColor(white: 0.08, alpha: prefs.backgroundOpacity)
        view.linkHighlightColor = prefs.linkHighlightColor()
        view.wantsLayer = true
        view.layer?.isOpaque = false
        view.layer?.backgroundColor = NSColor.clear.cgColor
    }

    /// Startup options for a new terminal. The preferred cursor becomes both the
    /// initial style and the style restored by `CSI 0 SP q`.
    static func terminalOptions(for prefs: Preferences) -> TerminalOptions {
        var options = TerminalOptions.default
        options.cursorStyle = cursorStyle(for: prefs)
        return options
    }

    nonisolated static func cursorStyle(for prefs: Preferences) -> CursorStyle {
        switch (prefs.cursorShape, prefs.cursorBlink) {
        case (.block, true): return .blinkBlock
        case (.block, false): return .steadyBlock
        case (.underline, true): return .blinkUnderline
        case (.underline, false): return .steadyUnderline
        case (.bar, true): return .blinkBar
        case (.bar, false): return .steadyBar
        }
    }

    @discardableResult
    static func flashBell(in view: LocalProcessTerminalView) -> Bool {
        guard PreferencesStore.standard.load().visualBell else { return false }
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

/// Remembers the cursor preference already applied to one terminal. Programs
/// such as vim or zsh vi-mode change the cursor themselves, so an unchanged
/// preference must not be sent again when the panel shows or settings reload.
struct TerminalCursorStyleTracker {
    private(set) var applied: CursorStyle

    /// Returns the DECSCUSR sequence to send, or nil when the preferred style
    /// has not changed since it was last applied.
    mutating func sequenceToApply(for prefs: Preferences) -> String? {
        let style = TerminalAppearance.cursorStyle(for: prefs)
        guard style != applied else { return nil }
        applied = style
        return prefs.cursorDECSCUSR
    }
}
