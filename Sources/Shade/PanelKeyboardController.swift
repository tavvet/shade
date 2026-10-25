import AppKit
import SwiftTerm
import ShadeCore

enum PanelShortcut: Equatable {
    case zoomIn
    case zoomOut
    case resetZoom
    case newTab
    case closeTab
    case clearScreen
    case selectTab(Int)
    case nextTab
    case previousTab
    case previousPrompt
    case nextPrompt
    case copyLastCommandOutput
    case showConnections
    case connectQuickSlot(Int)
}

/// Converts a key event into a Shade command without touching application state.
enum PanelShortcutResolver {
    static func resolve(
        keyCode: UInt16,
        charactersIgnoringModifiers: String,
        modifierFlags: NSEvent.ModifierFlags,
        tabCount: Int
    ) -> PanelShortcut? {
        let userKeys: NSEvent.ModifierFlags = [.shift, .control, .option, .command]
        let flags = modifierFlags.intersection(userKeys)
        let command: NSEvent.ModifierFlags = [.command]
        let control: NSEvent.ModifierFlags = [.control]
        let controlShift: NSEvent.ModifierFlags = [.control, .shift]
        let commandShift: NSEvent.ModifierFlags = [.command, .shift]
        let letter = KeyCodes.asciiLetterForKeyCode[keyCode]

        if keyCode == KeyCodes.equal, flags == command || flags == commandShift {
            return .zoomIn
        }
        if flags == command, keyCode == KeyCodes.minus {
            return .zoomOut
        }
        if flags == command, keyCode == KeyCodes.zero {
            return .resetZoom
        }

        if flags == command {
            switch letter {
            case "t": return .newTab
            case "w": return .closeTab
            case "k": return .clearScreen
            default:
                if let digit = Int(charactersIgnoringModifiers), (1...9).contains(digit) {
                    let index = digit - 1
                    return index < tabCount ? .selectTab(index) : nil
                }
            }
        }

        if keyCode == KeyCodes.tab, flags == control {
            return .nextTab
        }
        if keyCode == KeyCodes.tab, flags == controlShift {
            return .previousTab
        }

        if flags == commandShift {
            if let digit = KeyCodes.digitForKeyCode[keyCode] {
                return .connectQuickSlot(digit)
            }
            switch keyCode {
            case KeyCodes.upArrow: return .previousPrompt
            case KeyCodes.downArrow: return .nextPrompt
            default:
                if letter == "o" { return .copyLastCommandOutput }
                if letter == "p" { return .showConnections }
            }
        }

        return nil
    }
}

/// Handles panel-level shortcuts and forwards terminal-specific input.
@MainActor
final class PanelKeyboardController: PanelKeyHandler {
    private let terminals: TerminalsController
    private let preferences: any PreferencesStoring
    private let showConnections: @MainActor () -> Void
    private let connectQuickSlot: @MainActor (Int) -> Void
    /// The latest zoom; each one is a single store transaction, and the store
    /// runs them in the order the key presses arrived.
    private var lastZoom: Task<Void, Never>?

    init(
        terminals: TerminalsController,
        preferences: any PreferencesStoring,
        showConnections: @escaping @MainActor () -> Void = {},
        connectQuickSlot: @escaping @MainActor (Int) -> Void = { _ in }
    ) {
        self.terminals = terminals
        self.preferences = preferences
        self.showConnections = showConnections
        self.connectQuickSlot = connectQuickSlot
    }

    func panelDidReceiveUserInput() {
        terminals.noteUserInput()
    }

    func waitForPendingSave() async { await lastZoom?.value }

    func panelHandleKey(_ event: NSEvent) -> Bool {
        guard let shortcut = PanelShortcutResolver.resolve(
            keyCode: event.keyCode,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
            modifierFlags: event.modifierFlags,
            tabCount: terminals.sessions.count
        ) else { return false }

        perform(shortcut)
        return true
    }

    func panelHandleTerminalInput(_ input: PanelTerminalInput) {
        guard let session = terminals.activeSession else { return }
        switch input {
        case .bytes(let bytes):
            session.sendUserInput(bytes)
        case .selection(let direction, let byWord):
            session.view.extendShadeKeyboardSelection(direction: direction, byWord: byWord)
        }
    }

    /// Copies the terminal selection and removes the corresponding number of
    /// characters to the left of the shell cursor using DEL bytes.
    func cutSelection() {
        guard let session = terminals.activeSession,
              let text = session.view.getSelection(),
              !text.isEmpty else { return }
        let view = session.view
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        session.sendUserInput([UInt8](repeating: 0x7F, count: text.count))
        view.selectNone()
    }

    private func perform(_ shortcut: PanelShortcut) {
        switch shortcut {
        case .zoomIn:
            adjustFontSize(by: 1)
        case .zoomOut:
            adjustFontSize(by: -1)
        case .resetZoom:
            adjustFontSize(by: nil)
        case .newTab:
            terminals.newSession()
        case .closeTab:
            terminals.closeActive()
        case .clearScreen:
            clearVisibleScreen()
        case .selectTab(let index):
            terminals.select(at: index)
        case .nextTab:
            terminals.selectNext()
        case .previousTab:
            terminals.selectPrev()
        case .previousPrompt:
            terminals.activeSession?.jumpToPreviousPrompt()
        case .nextPrompt:
            terminals.activeSession?.jumpToNextPrompt()
        case .copyLastCommandOutput:
            terminals.activeSession?.copyLastCommandOutput()
        case .showConnections:
            showConnections()
        case .connectQuickSlot(let number):
            connectQuickSlot(number)
        }
    }

    private func adjustFontSize(by delta: CGFloat?) {
        let store = preferences
        lastZoom = Task { @MainActor in
            do {
                // Read, zoom and save happen in one store transaction; the
                // store announces the new size to its observers.
                try await store.updateFontSize { Preferences.zoomedFontSize(from: $0, delta: delta) }
            } catch {
                NSLog("Shade: cannot save font size: %@", error.localizedDescription)
                NSSound.beep()
            }
        }
    }

    /// Clears previous output locally without submitting or rewriting shell input.
    private func clearVisibleScreen() {
        guard let session = terminals.activeSession else { return }
        let view = session.view
        guard !view.hasMarkedText(),
              view.clearPreviousOutput(
                preservePrompt: !session.isCommandRunning
              ) else { return }
        session.invalidatePromptHistoryCoordinates()
        view.selectNone()
        view.scroll(toPosition: 1)
        view.needsDisplay = true
    }
}
