import AppKit
import ShadeCore

/// Asks whether to quit while tabs the user cares about are open.
@MainActor
enum QuitConfirmationAlert {
    /// Shows the question and returns true when the user chooses Quit.
    static func run(_ tabs: [QuitWarning.Tab]) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Quit Shade?"
        alert.informativeText = QuitWarning.message(for: tabs)
        let quit = alert.addButton(withTitle: "Quit")
        quit.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        // A quit sent by another app arrives while Shade is in the background.
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// True for the quit event macOS sends when logging out, restarting or
    /// shutting down; only that event carries a quit reason. ⌘Q has no event.
    static func isSessionEnding(_ event: NSAppleEventDescriptor?) -> Bool {
        guard let event,
              event.eventClass == coreEventClass,
              event.eventID == quitEventID else { return false }
        return event.attributeDescriptor(forKeyword: quitReasonKeyword) != nil
            || event.paramDescriptor(forKeyword: quitReasonKeyword) != nil
    }

    static let coreEventClass: AEEventClass = 0x6165_7674    // 'aevt'
    static let quitEventID: AEEventID = 0x7175_6974          // 'quit'
    static let quitReasonKeyword: AEKeyword = 0x7768_793F    // 'why?' (kAEQuitReason)
}
