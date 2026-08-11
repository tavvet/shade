import Foundation

/// Owns the repeating timer used to refresh terminal context while the panel
/// is visible. The refresh action remains supplied by the caller so polling
/// cadence is independent from session collection and Git refresh policy.
@MainActor
final class TerminalContextPoller {
    typealias Cancellation = @MainActor () -> Void
    typealias Scheduler = @MainActor (
        _ interval: TimeInterval,
        _ tick: @escaping @MainActor () -> Void
    ) -> Cancellation

    private let interval: TimeInterval
    private let scheduler: Scheduler
    private let poll: @MainActor () -> Void
    private var cancelScheduledPoll: Cancellation?

    var isRunning: Bool { cancelScheduledPoll != nil }

    init(
        interval: TimeInterval = 1,
        scheduler: @escaping Scheduler = TerminalContextPoller.scheduleTimer,
        poll: @escaping @MainActor () -> Void
    ) {
        self.interval = interval
        self.scheduler = scheduler
        self.poll = poll
    }

    /// Polls immediately and starts the repeating timer. Idempotent.
    func resume() {
        guard cancelScheduledPoll == nil else { return }
        poll()
        cancelScheduledPoll = scheduler(interval) { [weak self] in
            guard let self, self.isRunning else { return }
            self.poll()
        }
    }

    func pause() {
        cancelScheduledPoll?()
        cancelScheduledPoll = nil
    }

    private static func scheduleTimer(
        interval: TimeInterval,
        tick: @escaping @MainActor () -> Void
    ) -> Cancellation {
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in tick() }
        }
        let cancellation = TimerCancellation(timer: timer)
        return { cancellation.cancel() }
    }
}

/// Invalidates a scheduled Foundation timer when its owning cancellation
/// closure is released, including when the poller itself is deallocated.
private final class TimerCancellation {
    private let timer: Timer

    init(timer: Timer) {
        self.timer = timer
    }

    func cancel() {
        timer.invalidate()
    }

    deinit {
        timer.invalidate()
    }
}
