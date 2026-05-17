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

    init() {
        containerView.translatesAutoresizingMaskIntoConstraints = false
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
        guard sessions.indices.contains(activeIndex) else { return }
        let closing = sessions.remove(at: activeIndex)
        closing.terminate()
        if sessions.isEmpty {
            newSession()       // always keep at least one
        } else {
            select(at: min(activeIndex, sessions.count - 1))
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
