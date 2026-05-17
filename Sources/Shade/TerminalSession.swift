import AppKit
import SwiftTerm

/// Thin wrapper around SwiftTerm's LocalProcessTerminalView that owns one shell session.
@MainActor
final class TerminalSession: NSObject {
    static let titleDidChange = Notification.Name("ShadeTerminalSessionTitleDidChange")

    let view: LocalProcessTerminalView

    private(set) var title: String = "" {
        didSet { notifyTitleChanged() }
    }

    private var cwd: String = "" {
        didSet {
            // CWD changes also affect displayTitle when no explicit title was set.
            guard title.isEmpty else { return }
            notifyTitleChanged()
        }
    }

    private(set) var branch: String = "" {
        didSet { notifyTitleChanged() }
    }

    private(set) var gitStatus: GitStatus? = nil {
        didSet {
            guard oldValue != gitStatus else { return }
            notifyTitleChanged()
        }
    }

    let shellName: String

    /// What the tab bar shows: shell-provided title or abbreviated CWD or shell name.
    /// The git branch is rendered separately as a floating badge over the terminal.
    var displayTitle: String {
        if !title.isEmpty { return title }
        if !cwd.isEmpty   { return abbreviateHome(cwd) }
        return shellName
    }

    private func notifyTitleChanged() {
        NotificationCenter.default.post(name: Self.titleDidChange, object: self)
    }

    private func abbreviateHome(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    override init() {
        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        shellName = (shellPath as NSString).lastPathComponent
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

    /// Re-read the shell's working directory and current git branch.
    /// Called by the controller's polling timer. `includeGitStatus` is true only for the
    /// active session — `git status` / `git diff` are subprocesses, and running them every
    /// tick for every tab would be heavy in large repos. Non-active tabs' working directory
    /// can't change without user input anyway, so their status is only refreshed when they
    /// become active (via `select`).
    func refreshContext(includeGitStatus: Bool) {
        guard view.process.running else { return }
        if let path = ProcessCwd.read(pid: view.process.shellPid), path != cwd {
            cwd = path
        }
        let newBranch = cwd.isEmpty ? "" : (GitInfo.branch(forCwd: cwd) ?? "")
        if newBranch != branch {
            branch = newBranch
        }

        guard includeGitStatus else { return }
        let pathSnapshot = cwd
        let inRepo = !branch.isEmpty
        Task.detached(priority: .utility) { [weak self] in
            let status: GitStatus? = inRepo ? GitInfo.status(forCwd: pathSnapshot) : nil
            await MainActor.run {
                guard let self else { return }
                self.gitStatus = status
            }
        }
    }
}

extension TerminalSession: LocalProcessTerminalViewDelegate {
    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.title = title
            }
        }
    }
    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        let path = directory ?? ""
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.cwd = path
            }
        }
    }

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                // Auto-restart so the panel always shows a live shell.
                self?.start()
            }
        }
    }
}
