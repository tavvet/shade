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
    var onBell: (() -> Bool)?
    var onPromptMark: (([UInt8], Int) -> Void)?
    var onTitleChange: ((String) -> Void)?
    var onCwdChange: ((String) -> Void)?
    var onUserInput: (() -> Void)?

    private let delegateProxy: TerminalDelegateProxy
    private let activityView: ActivityTerminalView
    private var didPadInitialPrompt = false

    override init() {
        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        shellName = (shellPath as NSString).lastPathComponent

        let activityView = ActivityTerminalView(frame: .zero)
        self.activityView = activityView
        view = activityView
        delegateProxy = TerminalDelegateProxy(forward: activityView.terminalDelegate)
        super.init()

        view.processDelegate = self
        view.terminalDelegate = delegateProxy
        delegateProxy.onOpenLink = { [weak self] link in
            MainActor.assumeIsolated { self?.onOpenLink?(link) }
        }
        delegateProxy.onBell = { [weak self] in
            MainActor.assumeIsolated { self?.onBell?() ?? false }
        }
        activityView.onData = { [weak self] in
            MainActor.assumeIsolated { self?.onActivity?() }
        }
        activityView.onUserInput = { [weak self] in
            MainActor.assumeIsolated { self?.onUserInput?() }
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
    var foregroundProcessGroup: Int32? {
        let fileDescriptor = view.process.childfd
        guard fileDescriptor >= 0 else { return nil }
        let processGroup = tcgetpgrp(fileDescriptor)
        return processGroup > 0 ? processGroup : nil
    }

    func start() {
        guard !isRunning else { return }
        if !didPadInitialPrompt {
            padCursorToBottom()
            didPadInitialPrompt = true
        }
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let environment = ShellIntegration.environment(
            shellName: shellName,
            enabled: PreferencesStore.standard.load().shellEnrichment
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

    func sendUserInput(_ bytes: [UInt8]) {
        activityView.sendUserInput(bytes)
    }

    func showRespawnStoppedNotice() {
        view.feed(
            text: "\r\n[Shade] Shell exited repeatedly; automatic restart stopped. "
                + "Press ⌘W to retry.\r\n"
        )
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
