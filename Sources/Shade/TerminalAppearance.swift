import AppKit
import SwiftTerm

/// Applies user appearance preferences and transient visual effects to a
/// SwiftTerm view without making the session coordinator own rendering details.
@MainActor
enum TerminalAppearance {
    /// Applies the preferences that differ from `previous`, or all of them when
    /// `previous` is nil. SwiftTerm setters have side effects even for equal
    /// values: assigning a font clears the selection and recomputes cell
    /// metrics, and color changes force a full redraw.
    static func apply(
        _ prefs: Preferences,
        replacing previous: Preferences?,
        to view: LocalProcessTerminalView
    ) {
        if previous?.fontName != prefs.fontName || previous?.fontSize != prefs.fontSize {
            view.font = prefs.terminalFont()
        }
        if previous?.backgroundOpacity != prefs.backgroundOpacity {
            view.nativeBackgroundColor = NSColor(white: 0.08, alpha: prefs.backgroundOpacity)
        }
        if previous?.linkHighlightHex != prefs.linkHighlightHex {
            view.linkHighlightColor = prefs.linkHighlightColor()
        }
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

    /// DECSCUSR (`CSI Ps SP q`) that selects `style`.
    nonisolated static func decscusrSequence(for style: CursorStyle) -> String {
        let parameter: Int
        switch style {
        case .blinkBlock: parameter = 1
        case .steadyBlock: parameter = 2
        case .blinkUnderline: parameter = 3
        case .steadyUnderline: parameter = 4
        case .blinkBar: parameter = 5
        case .steadyBar: parameter = 6
        }
        return "\u{1B}[\(parameter) q"
    }

    static func flashBell(in view: LocalProcessTerminalView) {
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
    }
}

/// Remembers the cursor preference already applied to one terminal. Programs
/// such as vim or zsh vi-mode change the cursor themselves, so an unchanged
/// preference must not be sent again when the panel shows or settings reload.
struct TerminalCursorStyleTracker {
    private(set) var applied: CursorStyle
    private(set) var preferred: CursorStyle

    init(applied: CursorStyle) {
        self.applied = applied
        preferred = applied
    }

    /// Records the preferred style and returns the DECSCUSR sequence to send
    /// now, or nil when it is already applied. A full-screen program owns the
    /// cursor while the alternate screen is active, so a changed preference
    /// stays pending until a later call made from the normal screen.
    mutating func sequenceToApply(
        for prefs: Preferences,
        isAlternateScreen: Bool
    ) -> String? {
        preferred = TerminalAppearance.cursorStyle(for: prefs)
        guard preferred != applied, !isAlternateScreen else { return nil }
        applied = preferred
        return TerminalAppearance.decscusrSequence(for: preferred)
    }
}
