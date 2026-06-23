import AppKit

/// Owns the collection of terminal sessions inside the dropdown panel.
/// Knows the active tab and is the single entry point for tab operations.
@MainActor
final class TerminalsController {
    let containerView = NSView()

    private(set) var sessions: [TerminalSession] = []
    private(set) var activeIndex: Int = -1

    /// Set by AppDelegate; forwarded from each session's `onCommandFinish`.
    var commandFinishHandler: ((TimeInterval, Int?, String) -> Void)?

    /// Posted whenever the tab set or selection changes (the tab bar observes it via TabsObservable).
    static let tabsChanged = Notification.Name("ShadeTerminalsTabsChanged")

    private var cwdTimer: Timer?

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
        guard cwdTimer == nil else { return }
        pollOnce()
        cwdTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollOnce() }
        }
    }

    /// Stops the poll while the panel is hidden — nothing it updates is on-screen,
    /// so the per-second cwd / git / process work would be pure idle drain.
    func pausePolling() {
        cwdTimer?.invalidate()
        cwdTimer = nil
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
            if let index = self.sessions.firstIndex(where: { $0 === session }) {
                self.close(at: index)
            }
        }
        session.onCommandFinish = { [weak self] duration, exitCode, cwd in
            self?.commandFinishHandler?(duration, exitCode, cwd)
        }
        sessions.append(session)
        select(at: sessions.count - 1)
        return session
    }

    func closeActive() {
        close(at: activeIndex)
    }

    func close(at index: Int) {
        guard sessions.indices.contains(index) else { return }
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
