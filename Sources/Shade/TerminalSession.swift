import AppKit
import SwiftTerm

/// Thin wrapper around SwiftTerm's LocalProcessTerminalView that owns one shell session.
@MainActor
final class TerminalSession: NSObject {
    let view: LocalProcessTerminalView

    override init() {
        view = LocalProcessTerminalView(frame: .zero)
        super.init()
        view.processDelegate = self
        view.translatesAutoresizingMaskIntoConstraints = false
        view.nativeForegroundColor = NSColor(white: 0.92, alpha: 1.0)
        apply(Preferences.load())
    }

    func start() {
        guard !view.process.running else { return }
        padCursorToBottom()
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let shellName = (shell as NSString).lastPathComponent
        view.startProcess(
            executable: shell,
            args: ["-l"],
            environment: nil,
            execName: "-" + shellName  // leading dash → login shell
        )
    }

    /// Push the emulator cursor to the last visible row so the shell prompt
    /// appears at the bottom of the panel (Guake-style), not the top.
    func padCursorToBottom() {
        let rows = view.getTerminal().rows
        guard rows > 1 else { return }
        view.feed(text: String(repeating: "\n", count: rows - 1))
    }

    func apply(_ prefs: Preferences) {
        view.font = prefs.terminalFont()
        view.nativeBackgroundColor = NSColor(white: 0.08, alpha: prefs.backgroundOpacity)
        view.wantsLayer = true
        view.layer?.isOpaque = false
        view.layer?.backgroundColor = NSColor.clear.cgColor
    }

    func terminate() {
        if view.process.running {
            kill(view.process.shellPid, SIGTERM)
        }
    }
}

extension TerminalSession: LocalProcessTerminalViewDelegate {
    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                // Auto-restart so the panel always shows a live shell.
                self?.start()
            }
        }
    }
}
