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
        configureAppearance()
    }

    func start() {
        guard !view.process.running else { return }
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let shellName = (shell as NSString).lastPathComponent
        view.startProcess(
            executable: shell,
            args: ["-l"],
            environment: nil,
            execName: "-" + shellName  // leading dash → login shell
        )
    }

    private func configureAppearance() {
        view.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        view.nativeBackgroundColor = NSColor(white: 0.08, alpha: 1.0)
        view.nativeForegroundColor = NSColor(white: 0.92, alpha: 1.0)
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
