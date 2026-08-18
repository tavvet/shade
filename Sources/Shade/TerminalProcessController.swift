import AppKit
import SwiftTerm

/// Owns SwiftTerm's view and process lifecycle for one tab. It converts
/// delegate/parser callbacks into main-actor closures so the session layer does
/// not need to implement SwiftTerm protocols or manage their threading rules.
@MainActor
final class TerminalProcessController: NSObject {
    typealias ProcessStarter = @MainActor (
        _ view: LocalProcessTerminalView,
        _ executable: String,
        _ arguments: [String],
        _ environment: [String]?,
        _ execName: String?,
        _ currentDirectory: String?
    ) -> Bool

    let view: LocalProcessTerminalView
    let shellName: String

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
    private let launchConfiguration: TerminalLaunchConfiguration
    private let shellPath: String
    private let processStarter: ProcessStarter
    private var didPadInitialPrompt = false
    private var didStartProcess = false

    init(
        configuration: TerminalLaunchConfiguration = TerminalLaunchConfiguration(),
        shellPath: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh",
        processStarter: ProcessStarter? = nil
    ) {
        self.shellPath = shellPath
        shellName = (shellPath as NSString).lastPathComponent
        launchConfiguration = configuration
        self.processStarter = processStarter ?? { view, executable, arguments, environment,
                                                   execName, currentDirectory in
            view.startProcess(
                executable: executable,
                args: arguments,
                environment: environment,
                execName: execName,
                currentDirectory: currentDirectory
            )
            // SwiftTerm does not return a launch result. It assigns shellPid only
            // after forkpty succeeds, and leaves it at zero when PTY creation fails.
            return view.process.shellPid > 0
        }

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
        activityView.onOSC133 = { [weak self] payload, row in
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
        guard !isRunning,
              !didStartProcess else { return }
        if !didPadInitialPrompt {
            padCursorToBottom()
            didPadInitialPrompt = true
        }
        let shellEnvironment = ShellIntegration.environment(
            shellName: shellName,
            enabled: PreferencesStore.standard.load().shellEnrichment
        )
        if let initialCommand = launchConfiguration.initialCommand {
            didStartProcess = startCommandSequence(
                initialCommand,
                shellEnvironment: shellEnvironment
            )
        } else {
            didStartProcess = startLoginShell(environment: shellEnvironment)
        }
    }

    private func startCommandSequence(
        _ initialCommand: ProcessInvocation,
        shellEnvironment: [String]?
    ) -> Bool {
        let invocation = TerminalCommandSequence.invocation(
            initialCommand: initialCommand,
            loginShellPath: shellPath
        )
        let environment = TerminalCommandSequence.environment(
            shellIntegrationEnvironment: shellEnvironment
        )
        return processStarter(
            view,
            invocation.executable,
            invocation.arguments,
            environment,
            nil,
            launchConfiguration.startupDirectory
        )
    }

    private func startLoginShell(environment: [String]?) -> Bool {
        processStarter(
            view,
            shellPath,
            ["-l"],
            environment,
            "-" + shellName,
            launchConfiguration.startupDirectory
        )
    }

    func terminate() {
        if isRunning {
            // forkpty makes the PTY owner its process-group leader. A configured
            // command is a child of our wrapper, so terminate the complete group
            // and prevent the wrapper from continuing into the login shell.
            let pid = shellPid
            if getpgid(pid) != pid || kill(-pid, SIGTERM) != 0 {
                kill(pid, SIGTERM)
            }
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
