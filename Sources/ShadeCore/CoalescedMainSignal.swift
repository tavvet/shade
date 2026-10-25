import Dispatch
import os

/// Collapses signals raised on any thread into main-actor calls: signals that
/// arrive before the pending call runs share it. The pending flag is cleared
/// before the action runs, so a signal raised during or after the action
/// schedules the next call and none is lost.
public final class CoalescedMainSignal: Sendable {
    private let pending = OSAllocatedUnfairLock(initialState: false)
    private let action: @MainActor @Sendable () -> Void

    public init(_ action: @escaping @MainActor @Sendable () -> Void) {
        self.action = action
    }

    public func signal() {
        let shouldSchedule = pending.withLock { isPending -> Bool in
            guard !isPending else { return false }
            isPending = true
            return true
        }
        guard shouldSchedule else { return }
        DispatchQueue.main.async { [self] in
            pending.withLock { $0 = false }
            MainActor.assumeIsolated { action() }
        }
    }
}
