import AppKit

/// Owns the collection of terminal sessions inside the dropdown panel.
/// Knows the active tab and is the single entry point for tab operations.
@MainActor
final class TerminalsController {
    let containerView = NSView()

    private(set) var sessions: [TerminalSession] = []
    private(set) var activeIndex: Int = -1

    /// Consumed by the notification coordinator; forwarded from each session's
    /// `onCommandFinish`.
    var commandFinishHandler: ((TimeInterval, Int?, String) -> Void)?

    /// Posted whenever the tab set or selection changes (the tab bar observes it via TabsObservable).
    static let tabsChanged = Notification.Name("ShadeTerminalsTabsChanged")

    private lazy var contextPoller = TerminalContextPoller { [weak self] in
        self?.pollOnce()
    }
    private var automaticRespawnLimiter = AutomaticSessionRespawnLimiter()

    init() {
        containerView.translatesAutoresizingMaskIntoConstraints = false
    }

    /// One context refresh across every session: cwd / remote indicator for all
    /// tabs (their labels show it), plus a weak git-status fallback for the active
    /// tab when the shell hasn't installed Shade's OSC 133 integration. All fast,
    /// in-process reads.
    private func pollOnce() {
        for session in sessions { session.refreshContext() }
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
        guard sessions.indices.contains(activeIndex) else { return nil }
        return sessions[activeIndex]
    }

    func ensureAtLeastOneSession() {
        if sessions.isEmpty { newSession() }
    }

    @discardableResult
    func newSession() -> TerminalSession {
        // TerminalSession.init already calls apply(Preferences.load()).
        let session = TerminalSession()
        // ⌘T can open in the active tab's directory instead of $HOME. The first tab
        // and the last-tab respawn have no active session, so they keep $HOME.
        if Preferences.load().newTabInheritsCwd, let cwd = activeSession?.cwd, !cwd.isEmpty {
            session.startupDirectory = cwd
        }
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
        sessions.append(session)
        select(at: sessions.count - 1)
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
        guard let index = sessions.firstIndex(where: { $0 === session }) else { return }
        if sessions.count == 1,
           !automaticRespawnLimiter.shouldAllowRespawn() {
            session.showRespawnStoppedNotice()
            return
        }
        close(at: index, origin: .processExit)
    }

    private func close(at index: Int, origin: CloseOrigin) {
        guard sessions.indices.contains(index) else { return }
        if origin == .userAction {
            automaticRespawnLimiter.reset()
        }
        let closing = sessions.remove(at: index)
        closing.terminate()
        if sessions.isEmpty {
            activeIndex = -1
            newSession()       // always keep at least one
        } else {
            let newActive = min(activeIndex >= index ? activeIndex - 1 : activeIndex, sessions.count - 1)
            activeIndex = max(0, newActive)
            select(at: activeIndex)
        }
    }

    private enum CloseOrigin: Equatable {
        case userAction
        case processExit
    }

    func select(at index: Int) {
        guard sessions.indices.contains(index) else { return }
        let session = sessions[index]
        containerView.subviews.forEach { $0.removeFromSuperview() }
        let v = session.view
        containerView.addSubview(v)
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: containerView.topAnchor),
            v.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            v.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            v.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
        ])
        // Resolve constraints now so SwiftTerm knows its rows before we start the shell
        // (otherwise the first prompt lands at the top because the terminal still has its
        // default 24-row buffer).
        containerView.layoutSubtreeIfNeeded()
        activeIndex = index
        for (i, s) in sessions.enumerated() { s.setActive(i == index) }
        session.start()
        // Refresh cwd/branch now and let the coordinator decide whether to
        // re-run git status (cwd change → strong, unchanged cwd within
        // cooldown → skip).
        session.tabActivated()
        containerView.window?.makeFirstResponder(v)
        NotificationCenter.default.post(name: Self.tabsChanged, object: self)
    }

    func selectNext() {
        guard !sessions.isEmpty else { return }
        select(at: (activeIndex + 1) % sessions.count)
    }

    func selectPrev() {
        guard !sessions.isEmpty else { return }
        select(at: (activeIndex - 1 + sessions.count) % sessions.count)
    }

    /// Assigns (or clears, when `name` is empty/whitespace) the user title of the
    /// tab at `index`. The session posts `titleDidChange`, refreshing the bar.
    func renameSession(at index: Int, to name: String) {
        guard sessions.indices.contains(index) else { return }
        sessions[index].setUserTitle(name)
    }

    func applyToAll(_ prefs: Preferences) {
        for session in sessions {
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
