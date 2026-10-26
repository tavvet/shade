import AppKit
import ShadeCore

/// Owns the collection of terminal sessions inside the dropdown panel.
/// Knows the active tab and is the single entry point for tab operations.
@MainActor
final class TerminalsController {
    private let viewHost: TerminalViewHost
    private let preferences: any PreferencesProviding
    var containerView: NSView { viewHost.containerView }

    private var tabs = TerminalTabStore<TerminalSession>()
    var sessions: [TerminalSession] { tabs.sessions }
    var activeIndex: Int { tabs.activeIndex }

    /// Forwarded from each session's `onCommandFinish`; the notification
    /// coordinator posts the user notification.
    var onCommandFinish: ((TimeInterval, Int?, String) -> Void)?

    /// Called after the tab set or selection changes, or when anything a tab
    /// shows changes (title, status dot, git badge). Each entry returns false
    /// once its owner is gone, so it is dropped on the next change.
    private var tabsObservers: [() -> Bool] = []

    private lazy var contextPoller = TerminalContextPoller { [weak self] in
        self?.pollOnce()
    }
    private var automaticRespawnLimiter = AutomaticSessionRespawnLimiter()
    /// One restart allowance per pinned session, re-armed by its user input.
    private var pinnedRestartLimiters: [UUID: AutomaticSessionRespawnLimiter] = [:]

    init(
        preferences: any PreferencesProviding,
        viewHost: TerminalViewHost = TerminalViewHost()
    ) {
        self.preferences = preferences
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
        let prefs = preferences.load()
        var configuration = TerminalLaunchConfiguration()
        if prefs.newTabInheritsCwd,
           let cwd = activeSession?.cwd,
           !cwd.isEmpty {
            configuration.startupDirectory = cwd
        }
        return newSession(configuration: configuration, preferences: prefs)
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
        newSession(configuration: configuration, preferences: preferences.load())
    }

    private func newSession(
        configuration: TerminalLaunchConfiguration,
        preferences prefs: Preferences
    ) -> TerminalSession {
        // TerminalSession.init applies these preferences to the new view.
        let session = TerminalSession(configuration: configuration, preferences: prefs)
        // Close this tab when the shell exits (Ctrl-D / `exit` / crash).
        // Weak self + weak session — onExit lives on the session, the
        // session is owned by `sessions`, and the closure must not keep
        // the controller alive on its own.
        session.onExit = { [weak self, weak session] in
            guard let self, let session else { return }
            self.sessionDidExit(session)
        }
        session.onCommandFinish = { [weak self] duration, exitCode, cwd in
            self?.onCommandFinish?(duration, exitCode, cwd)
        }
        session.onPresentationChange = { [weak self] in
            self?.notifyTabsObservers()
        }
        session.shouldFlashBell = { [weak self] in
            self?.preferences.load().visualBell ?? false
        }
        session.onUserInput = { [weak self, weak session] in
            self?.automaticRespawnLimiter.reset()
            if let session { self?.pinnedRestartLimiters[session.id]?.reset() }
        }
        let index = tabs.append(session)
        select(at: index)
        return session
    }

    /// Returns false when nothing closed, for example because the tab is pinned.
    @discardableResult
    func closeActive() -> Bool {
        close(at: activeIndex)
    }

    func noteUserInput() {
        automaticRespawnLimiter.reset()
        if let id = activeSession?.id { pinnedRestartLimiters[id]?.reset() }
    }

    /// Closes a tab unless it is pinned. Returns whether a tab closed.
    @discardableResult
    func close(at index: Int) -> Bool {
        guard !tabs.isPinned(at: index) else { return false }
        return close(at: index, origin: .userAction)
    }

    func isPinned(at index: Int) -> Bool {
        tabs.isPinned(at: index)
    }

    /// Pins or unpins a tab. Pinned tabs move to the left and cannot be closed.
    func togglePin(at index: Int) {
        guard let session = tabs.session(at: index) else { return }
        let pinned = !tabs.isPinned(at: index)
        guard tabs.setPinned(pinned, at: index) else { return }
        pinnedRestartLimiters[session.id] = pinned ? AutomaticSessionRespawnLimiter() : nil
        // A tab whose shell already exited (for example after a stopped
        // automatic restart) would otherwise stay empty and uncloseable.
        if pinned, !session.isProcessRunning {
            session.restartShell(shellEnrichment: preferences.load().shellEnrichment)
        }
        notifyTabsObservers()
    }

    func toggleActivePin() {
        togglePin(at: activeIndex)
    }

    private func sessionDidExit(_ session: TerminalSession) {
        guard let index = tabs.index(of: session) else { return }
        if tabs.isPinned(at: index) {
            // Pinning may already have restarted it before this exit arrived.
            guard !session.isProcessRunning else { return }
            let allowed = pinnedRestartLimiters[session.id, default: AutomaticSessionRespawnLimiter()]
                .shouldAllowRespawn()
            if !allowed || !session.restartShell(shellEnrichment: preferences.load().shellEnrichment) {
                session.showPinnedRestartStoppedNotice()
            }
            return
        }
        if tabs.sessions.count == 1,
           !automaticRespawnLimiter.shouldAllowRespawn() {
            session.showRespawnStoppedNotice()
            return
        }
        close(at: index, origin: .processExit)
    }

    @discardableResult
    private func close(at index: Int, origin: CloseOrigin) -> Bool {
        guard let closing = tabs.remove(at: index) else { return false }
        pinnedRestartLimiters[closing.id] = nil
        if origin == .userAction {
            automaticRespawnLimiter.reset()
        }
        closing.terminate()
        if tabs.isEmpty {
            newSession()       // always keep at least one
        } else {
            select(at: tabs.activeIndex)
        }
        return true
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
        session.start(shellEnrichment: preferences.load().shellEnrichment)
        // Refresh cwd/branch now and let the coordinator decide whether to
        // re-run git status (cwd change → strong, unchanged cwd within
        // cooldown → skip).
        session.tabActivated()
        viewHost.focus(v)
        notifyTabsObservers()
    }

    /// Calls `handler` with `owner` after every tab change for as long as
    /// `owner` is alive. Several observers can register; none replaces another.
    /// The handler receives the owner, so it need not capture it.
    func observeTabs<Owner: AnyObject>(
        by owner: Owner,
        _ handler: @escaping (Owner) -> Void
    ) {
        tabsObservers.append { [weak owner] in
            guard let owner else { return false }
            handler(owner)
            return true
        }
    }

    private func notifyTabsObservers() {
        // Observers registered while this change is delivered keep their place.
        let current = tabsObservers
        tabsObservers = []
        tabsObservers = current.filter { $0() } + tabsObservers
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
    /// tab at `index`. The session reports the change to the tab observers.
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
