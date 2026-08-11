import AppKit

enum PanelInputRouting {
    /// An `NSTextField` installs an `NSTextView` field editor as the window's
    /// first responder. While that editor is active, terminal-specific key
    /// translations and edit commands must stay on the normal responder chain.
    static func isEditingText(_ responder: NSResponder?) -> Bool {
        responder is NSTextView
    }
}

@MainActor
protocol PanelKeyHandler: AnyObject {
    /// Return true if the event was handled and should not propagate.
    func panelHandleKey(_ event: NSEvent) -> Bool

    /// Apply translated terminal input to the currently active session.
    func panelHandleTerminalInput(_ input: PanelTerminalInput)
}
