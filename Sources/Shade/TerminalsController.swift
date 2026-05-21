import AppKit

/// Owns the collection of terminal sessions inside the dropdown panel.
/// Knows the active tab and is the single entry point for tab operations.
@MainActor
final class TerminalsController {
    let containerView = NSView()

    private(set) var sessions: [TerminalSession] = []
    private(set) var activeIndex: Int = -1

    /// Posted whenever the tab set or selection changes (for the future tab bar UI).
    static let tabsChanged = Notification.Name("ShadeTerminalsTabsChanged")

    private var cwdTimer: Timer?

    init() {
        containerView.translatesAutoresizingMaskIntoConstraints = false
        startCwdPolling()
    }

    private func startCwdPolling() {
        // Polls cwd / branch / remote indicator only — fast, in-process reads.
        // If the shell has not installed Shade's OSC 133 integration, the active
        // session also gets a weak git-status fallback through GitRefreshCoordinator.
        cwdTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                for session in self.sessions {
                    session.refreshContext()
                }
                self.activeSession?.fallbackRefreshGitStatusIfNeeded()
            }
        }
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

    func applyToAll(_ prefs: Preferences) {
        for session in sessions {
            session.apply(prefs)
        }
    }
}
