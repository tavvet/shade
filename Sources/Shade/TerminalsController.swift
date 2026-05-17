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
        cwdTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sessions.forEach { $0.refreshContext() }
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
        let session = TerminalSession()
        session.apply(Preferences.load())
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
