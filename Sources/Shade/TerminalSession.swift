import AppKit
import SwiftTerm

/// Coordinates the process, context, presentation and prompt-history components
/// that make up one terminal tab.
@MainActor
final class TerminalSession {
    static let titleDidChange = Notification.Name("ShadeTerminalSessionTitleDidChange")
    let id = UUID()

    /// Invoked when the underlying shell process exits — whether via Ctrl-D
    /// on an empty prompt, an explicit `exit`, or a crash. The controller
    /// installs this on each new session to close the corresponding tab
    /// (its "always keep at least one tab" rule handles the last-tab case).
    /// Closure callback rather than a notification because `Notification`
    /// isn't Sendable across the parser → main hop under strict concurrency.
    var onExit: (@MainActor () -> Void)?

    /// Invoked when a command completes (OSC 133 C→D): duration, exit code, cwd.
    /// The notification coordinator uses it to post while Shade is hidden.
    var onCommandFinish: ((TimeInterval, Int?, String) -> Void)?

    /// Invoked before locally generated terminal input is sent to the shell.
    /// The tab controller uses it to re-arm its one-shot automatic respawn.
    var onUserInput: (() -> Void)?

    private let process: TerminalProcessController
    private let presentation: TerminalPresentationState
    private var promptHistory = TerminalPromptHistory()
    var promptMarks: [PromptMark] { promptHistory.marks }

    private lazy var contextTracker: TerminalContextTracker = {
        let tracker = TerminalContextTracker()
        tracker.onChange = { [weak self] change in
            self?.contextDidChange(change)
        }
        return tracker
    }()

    var cwd: String { contextTracker.cwd }
    var branch: String { contextTracker.branch }
    var gitStatus: GitStatus? { contextTracker.gitStatus }
    var remoteIndicator: String? { contextTracker.remoteIndicator }
    var userTitle: String? { presentation.userTitle }
    var lastExitCode: Int? { presentation.lastExitCode }
    var hasUnseenActivity: Bool { presentation.hasUnseenActivity }
    var isActive: Bool { presentation.isActive }
    var shellName: String { presentation.shellName }
    var view: LocalProcessTerminalView { process.view }

    /// What the tab bar shows: an explicit user name, else the shell-provided
    /// title or abbreviated CWD or shell name. The git branch is rendered
    /// separately as a floating badge over the terminal. When we're inside an
    /// ssh/mosh session, local cwd/branch info is meaningless, so we surface a
    /// "[ssh]"-style indicator instead (unless the user pinned a name).
    var displayTitle: String {
        presentation.displayTitle(remoteIndicator: remoteIndicator, cwd: cwd)
    }

    private func notifyTitleChanged() {
        NotificationCenter.default.post(name: Self.titleDidChange, object: self)
    }

    private func contextDidChange(_ change: TerminalContextTracker.Change) {
        // CWD only participates in the automatic title when the shell has not
        // supplied an OSC title. Git and remote changes always affect tab/badge UI.
        if change == .cwd, !presentation.oscTitle.isEmpty { return }
        notifyTitleChanged()
    }

    /// Sets or clears the user-assigned tab name. Whitespace is trimmed; an empty
    /// result clears back to the automatic title.
    func setUserTitle(_ raw: String) {
        presentation.setUserTitle(raw)
    }

    init(configuration: TerminalLaunchConfiguration = TerminalLaunchConfiguration()) {
        let processController = TerminalProcessController(configuration: configuration)
        process = processController
        presentation = TerminalPresentationState(shellName: processController.shellName)
        presentation.onChange = { [weak self] in self?.notifyTitleChanged() }
        if let title = configuration.title {
            presentation.setUserTitle(title)
        }
        process.onExit = { [weak self] in self?.onExit?() }
        process.onOpenLink = { [weak self] link in
            guard let self else { return }
            TerminalLinkOpener.open(link, cwd: self.cwd)
        }
        process.onActivity = { [weak self] in self?.presentation.noteActivity() }
        process.onBell = { [weak self] in
            guard let self else { return false }
            return TerminalAppearance.flashBell(in: self.view)
        }
        process.onPromptMark = { [weak self] payload, row in
            self?.recordPromptMark(payload: payload, row: row)
        }
        process.onTitleChange = { [weak self] in self?.presentation.setOscTitle($0) }
        process.onCwdChange = { [weak self] in self?.contextTracker.updateCwd($0) }
        process.onUserInput = { [weak self] in self?.onUserInput?() }
        apply(PreferencesStore.standard.load())
    }

    func start() {
        process.start()
    }

    func apply(_ prefs: Preferences) {
        TerminalAppearance.apply(prefs, to: view)
    }

    func terminate() {
        process.terminate()
    }

    func sendUserInput(_ bytes: [UInt8]) {
        process.sendUserInput(bytes)
    }

    /// Keep the final, terminated tab visible when its automatic replacement
    /// exits before receiving user input. The notice gives the user a recovery
    /// path while avoiding another automatic process launch.
    func showRespawnStoppedNotice() {
        presentation.setOscTitle("shell exited")
        process.showRespawnStoppedNotice()
    }

    private func recordPromptMark(payload: [UInt8], row: Int) {
        guard let completion = promptHistory.record(
            payload: payload,
            row: row,
            in: view.getTerminal()
        ) else { return }

        presentation.setLastExitCode(completion.exitCode)
        contextTracker.commandFinished(shellPid: process.shellPid)
        if let duration = completion.duration {
            onCommandFinish?(duration, completion.exitCode, cwd)
        }
    }

    /// Scroll the viewport up to the previous OSC 133 `A` (prompt-start) mark
    /// strictly above the current viewport top. Returns `false` if there is
    /// no earlier mark (already at the oldest prompt, or no marks at all).
    @discardableResult
    func jumpToPreviousPrompt() -> Bool {
        jump(direction: .previous)
    }

    /// Mirror of `jumpToPreviousPrompt()`, scrolling down to the next mark.
    @discardableResult
    func jumpToNextPrompt() -> Bool {
        jump(direction: .next)
    }

    /// Copy the most recently completed command's output to the system
    /// clipboard. Requires the shell to emit OSC 133 `C`/`D` around its
    /// commands (see the README "Shell integration" section). Returns
    /// `false` if no completed C/D pair exists or the command produced
    /// no output.
    @discardableResult
    func copyLastCommandOutput() -> Bool {
        guard let text = promptHistory.lastCommandOutput(in: view.getTerminal()) else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return true
    }

    private func jump(direction: TerminalPromptHistory.NavigationDirection) -> Bool {
        let terminal = view.getTerminal()
        guard let viewportRow = promptHistory.viewportRow(toward: direction, in: terminal) else {
            return false
        }
        view.scrollTo(row: viewportRow)
        return true
    }

    /// Re-read the shell's working directory and current git branch — both
    /// fast (libproc lookup + `.git/HEAD` read). `git status` is no longer
    /// part of this tick; it runs through `GitRefreshCoordinator`, driven by
    /// cwd changes and OSC 133 command-finished marks instead of polling.
    func refreshContext() {
        guard process.isRunning else { return }
        if contextTracker.refresh(
            shellPid: process.shellPid,
            foregroundProcessGroup: process.foregroundProcessGroup,
            isActive: isActive
        ) {
            // The remote shell typically pushes its own OSC 0 title, and after
            // `exit` the local shell may not reset it. ContextTracker masks the
            // local values; discard this separate presentation value here too.
            presentation.setOscTitle("")
        }
    }

    /// Called when this session's tab becomes active. Pulls fresh
    /// cwd/branch immediately and schedules a status refresh under a weak
    /// reason — the coordinator's rate limit will skip it if we just
    /// refreshed (e.g. tab switched twice within a few seconds).
    func tabActivated() {
        refreshContext()
        contextTracker.tabActivated()
    }

    /// Called when the panel regains key-window status. Same weak-reason
    /// schedule as `tabActivated()` — covers the case where the user made
    /// changes in another tool while the panel was hidden.
    func focusReturned() {
        contextTracker.focusReturned()
    }

    /// Called by the controller when this tab becomes (or stops being) the visible
    /// one. Activating clears the unseen-output dot — that's what "marks it read."
    func setActive(_ active: Bool) {
        presentation.setActive(active)
    }

    /// Keeps the git badge fresh for users who have not installed Shade's OSC 133
    /// shell snippet. Once we see command-finished marks, those become the precise
    /// trigger and this fallback stays quiet.
    func fallbackRefreshGitStatusIfNeeded() {
        guard process.isRunning else { return }
        contextTracker.fallbackRefreshGitStatusIfNeeded()
    }
}
