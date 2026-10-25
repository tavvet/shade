/// Pure collection and selection state for terminal tabs.
/// Process, view and notification side effects remain in TerminalsController.
public struct TerminalTabStore<Session: AnyObject> {
    public private(set) var sessions: [Session] = []
    public private(set) var activeIndex = -1

    public init() {}

    public var isEmpty: Bool { sessions.isEmpty }

    public var activeSession: Session? {
        session(at: activeIndex)
    }

    public func session(at index: Int) -> Session? {
        guard sessions.indices.contains(index) else { return nil }
        return sessions[index]
    }

    public func index(of session: Session) -> Int? {
        sessions.firstIndex(where: { $0 === session })
    }

    @discardableResult
    public mutating func append(_ session: Session) -> Int {
        sessions.append(session)
        return sessions.count - 1
    }

    @discardableResult
    public mutating func select(at index: Int) -> Bool {
        guard sessions.indices.contains(index) else { return false }
        activeIndex = index
        return true
    }

    /// Removes a tab and keeps the same logical selection when possible. When
    /// the active tab closes, the previous tab wins; closing the first tab
    /// selects the new first tab.
    @discardableResult
    public mutating func remove(at index: Int) -> Session? {
        guard sessions.indices.contains(index) else { return nil }
        let previousActiveIndex = activeIndex
        let removed = sessions.remove(at: index)

        guard !sessions.isEmpty else {
            activeIndex = -1
            return removed
        }

        if previousActiveIndex < 0 {
            activeIndex = 0
        } else {
            let candidate = previousActiveIndex >= index
                ? previousActiveIndex - 1
                : previousActiveIndex
            activeIndex = min(max(0, candidate), sessions.count - 1)
        }
        return removed
    }

    public var nextIndex: Int? {
        guard !sessions.isEmpty else { return nil }
        guard sessions.indices.contains(activeIndex) else { return 0 }
        return (activeIndex + 1) % sessions.count
    }

    public var previousIndex: Int? {
        guard !sessions.isEmpty else { return nil }
        guard sessions.indices.contains(activeIndex) else { return sessions.count - 1 }
        return (activeIndex - 1 + sessions.count) % sessions.count
    }
}
