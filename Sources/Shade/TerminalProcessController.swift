import AppKit
import SwiftTerm

/// Owns SwiftTerm's view and local shell process for one tab. It converts
/// delegate/parser callbacks into main-actor closures so the session layer does
/// not need to implement SwiftTerm protocols or manage their threading rules.
@MainActor
final class TerminalProcessController: NSObject {
    let view: LocalProcessTerminalView
    let shellName: String

    var startupDirectory: String?
    var onExit: (() -> Void)?
    var onOpenLink: ((String) -> Void)?
    var onActivity: (() -> Void)?
    var onBell: (() -> Void)?
    var onPromptMark: (([UInt8], Int) -> Void)?
    var onTitleChange: ((String) -> Void)?
    var onCwdChange: ((String) -> Void)?

    private let delegateProxy: TerminalDelegateProxy
    private var didPadInitialPrompt = false

    override init() {
        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        shellName = (shellPath as NSString).lastPathComponent

        let activityView = ActivityTerminalView(frame: .zero)
        view = activityView
        delegateProxy = TerminalDelegateProxy(forward: activityView.terminalDelegate)
        super.init()

        view.processDelegate = self
        view.terminalDelegate = delegateProxy
        delegateProxy.onOpenLink = { [weak self] link in
            MainActor.assumeIsolated { self?.onOpenLink?(link) }
        }
        delegateProxy.onBell = { [weak self] in
            MainActor.assumeIsolated { self?.onBell?() }
        }
        activityView.onData = { [weak self] in
            MainActor.assumeIsolated { self?.onActivity?() }
        }

        let terminal = view.getTerminal()
        terminal.registerOscHandler(code: 133) { [weak self, weak terminal] data in
            guard let terminal else { return }
            let row = terminal.scrollInvariantCursorRow
            let payload = Array(data)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.onPromptMark?(payload, row)
                }
            }
        }

        view.translatesAutoresizingMaskIntoConstraints = false
        view.nativeForegroundColor = NSColor(white: 0.92, alpha: 1.0)
    }

    var isRunning: Bool { view.process.running }
    var shellPid: Int32 { view.process.shellPid }

    func start() {
        guard !isRunning else { return }
        if !didPadInitialPrompt {
            padCursorToBottom()
            didPadInitialPrompt = true
        }
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let environment = ShellIntegration.environment(
            shellName: shellName,
            enabled: Preferences.load().shellEnrichment
        )
        view.startProcess(
            executable: shell,
            args: ["-l"],
            environment: environment,
            execName: "-" + shellName,
            currentDirectory: startupDirectory
        )
    }

    func terminate() {
        if isRunning {
            kill(shellPid, SIGTERM)
        }
    }

    private func padCursorToBottom() {
        let rows = view.getTerminal().rows
        guard rows > 1 else { return }
        view.feed(text: String(repeating: "\n", count: rows - 1))
    }
}

extension TerminalProcessController: LocalProcessTerminalViewDelegate {
    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.onTitleChange?(title) }
        }
    }

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        let path = directory ?? ""
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.onCwdChange?(path) }
        }
    }

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.onExit?() }
        }
    }
}
