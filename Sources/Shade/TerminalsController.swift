import AppKit

/// Owns the collection of terminal sessions inside the dropdown panel.
/// Knows the active tab and is the single entry point for tab operations.
@MainActor
final class TerminalsController {
    private let viewHost: TerminalViewHost
    var containerView: NSView { viewHost.containerView }

    private var tabs = TerminalTabStore<TerminalSession>()
    var sessions: [TerminalSession] { tabs.sessions }
    var activeIndex: Int { tabs.activeIndex }

    /// Consumed by the notification coordinator; forwarded from each session's
    /// `onCommandFinish`.
    var commandFinishHandler: ((TimeInterval, Int?, String) -> Void)?

    /// Posted whenever the tab set or selection changes (the tab bar observes it via TabsObservable).
    static let tabsChanged = Notification.Name("ShadeTerminalsTabsChanged")

    private lazy var contextPoller = TerminalContextPoller { [weak self] in
        self?.pollOnce()
    }
    private var automaticRespawnLimiter = AutomaticSessionRespawnLimiter()

    init(viewHost: TerminalViewHost = TerminalViewHost()) {
        self.viewHost = viewHost
    }

    /// One context refresh across every session: cwd / remote indicator for all
    /// tabs (their labels show it), plus a weak git-status fallback for the active
    /// tab when the shell hasn't installed Shade's OSC 133 integration. All fast,
    /// in-process reads.
    private func pollOnce() {
        for session in tabs.sessions { session.refreshContext() }
        activeSession?.fallbackRefreshGitStatusIfNeeded()
    }

    /// Starts the 1 Hz context poll, refreshing once immediately so the UI is
    /// current the moment the panel shows. Idempotent.
    func resumePolling() {
        contextPoller.resume()
    }

    /// Stops the poll while the panel is hidden — nothing it updates is on-screen,
    /// so the per-second cwd / git / process work would be pure idle drain.
    func pausePolling() {
        contextPoller.pause()
    }

    var activeSession: TerminalSession? {
        tabs.activeSession
    }

    func ensureAtLeastOneSession() {
        if tabs.isEmpty { newSession() }
    }

    @discardableResult
    func newSession() -> TerminalSession {
        // ⌘T can open in the active tab's directory instead of $HOME. The first tab
        // and the last-tab respawn have no active session, so they keep $HOME.
        var configuration = TerminalLaunchConfiguration()
        if PreferencesStore.standard.load().newTabInheritsCwd,
           let cwd = activeSession?.cwd,
           !cwd.isEmpty {
            configuration.startupDirectory = cwd
        }
        return newSession(configuration: configuration)
    }

    /// Opens a profile in a fresh tab. Validation and command construction
    /// happen before the tab collection is mutated, so invalid profiles cannot
    /// leave behind a partially initialized session.
    @discardableResult
    func connect(to profile: SSHProfile) throws -> TerminalSession {
        try newSession(configuration: SSHConnectionLaunch.configuration(for: profile))
    }

    @discardableResult
    func newSession(configuration: TerminalLaunchConfiguration) -> TerminalSession {
        // TerminalSession.init already applies the persisted preferences.
        let session = TerminalSession(configuration: configuration)
        // Close this tab when the shell exits (Ctrl-D / `exit` / crash).
        // Weak self + weak session — onExit lives on the session, the
        // session is owned by `sessions`, and the closure must not keep
        // the controller alive on its own.
        session.onExit = { [weak self, weak session] in
            guard let self, let session else { return }
            self.sessionDidExit(session)
        }
        session.onCommandFinish = { [weak self] duration, exitCode, cwd in
            self?.commandFinishHandler?(duration, exitCode, cwd)
        }
        session.onUserInput = { [weak self] in
            self?.automaticRespawnLimiter.reset()
        }
        let index = tabs.append(session)
        select(at: index)
        return session
    }

    func closeActive() {
        close(at: activeIndex)
    }

    func noteUserInput() {
        automaticRespawnLimiter.reset()
    }

    func close(at index: Int) {
        close(at: index, origin: .userAction)
    }

    private func sessionDidExit(_ session: TerminalSession) {
        guard let index = tabs.index(of: session) else { return }
        if tabs.sessions.count == 1,
           !automaticRespawnLimiter.shouldAllowRespawn() {
            session.showRespawnStoppedNotice()
            return
        }
        close(at: index, origin: .processExit)
    }

    private func close(at index: Int, origin: CloseOrigin) {
        guard let closing = tabs.remove(at: index) else { return }
        if origin == .userAction {
            automaticRespawnLimiter.reset()
        }
        closing.terminate()
        if tabs.isEmpty {
            newSession()       // always keep at least one
        } else {
            select(at: tabs.activeIndex)
        }
    }

    private enum CloseOrigin: Equatable {
        case userAction
        case processExit
    }

    func select(at index: Int) {
        guard let session = tabs.session(at: index) else { return }
        let v = session.view
        viewHost.show(v)
        tabs.select(at: index)
        for (i, s) in tabs.sessions.enumerated() { s.setActive(i == index) }
        session.start()
        // Refresh cwd/branch now and let the coordinator decide whether to
        // re-run git status (cwd change → strong, unchanged cwd within
        // cooldown → skip).
        session.tabActivated()
        viewHost.focus(v)
        NotificationCenter.default.post(name: Self.tabsChanged, object: self)
    }

    func focusActiveSession() {
        guard let view = activeSession?.view else { return }
        viewHost.focus(view)
    }

    func selectNext() {
        guard let index = tabs.nextIndex else { return }
        select(at: index)
    }

    func selectPrev() {
        guard let index = tabs.previousIndex else { return }
        select(at: index)
    }

    /// Assigns (or clears, when `name` is empty/whitespace) the user title of the
    /// tab at `index`. The session posts `titleDidChange`, refreshing the bar.
    func renameSession(at index: Int, to name: String) {
        tabs.session(at: index)?.setUserTitle(name)
    }

    func applyToAll(_ prefs: Preferences) {
        for session in tabs.sessions {
            session.apply(prefs)
        }
    }
}

/// Allows one automatic replacement of the last session. Another automatic
/// respawn is permitted only after explicit user input, so a shell that exits
/// during startup can never create an unbounded fork/exit loop regardless of
/// how long its startup files take.
struct AutomaticSessionRespawnLimiter {
    private var hasAutomaticRespawned = false

    mutating func shouldAllowRespawn() -> Bool {
        guard !hasAutomaticRespawned else { return false }
        hasAutomaticRespawned = true
        return true
    }

    mutating func reset() {
        hasAutomaticRespawned = false
    }
}
