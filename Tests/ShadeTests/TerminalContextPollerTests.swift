import XCTest
@testable import Shade

final class TerminalContextPollerTests: XCTestCase {
    func testResumePollsImmediatelySchedulesTicksAndIsIdempotent() async {
        await MainActor.run {
            var pollCount = 0
            let scheduler = ManualPollingScheduler()
            let poller = TerminalContextPoller(
                interval: 60,
                scheduler: scheduler.schedule
            ) {
                pollCount += 1
            }

            poller.resume()
            poller.resume()

            XCTAssertEqual(pollCount, 1)
            XCTAssertEqual(scheduler.scheduleCount, 1)
            XCTAssertEqual(scheduler.interval, 60)
            XCTAssertTrue(poller.isRunning)

            scheduler.fire()

            XCTAssertEqual(pollCount, 2)
            poller.pause()
        }
    }

    func testPauseAllowsPollingToResume() async {
        await MainActor.run {
            var pollCount = 0
            let scheduler = ManualPollingScheduler()
            let poller = TerminalContextPoller(scheduler: scheduler.schedule) {
                pollCount += 1
            }

            poller.resume()
            poller.pause()
            XCTAssertFalse(poller.isRunning)
            XCTAssertEqual(scheduler.cancelCount, 1)

            scheduler.fire()
            XCTAssertEqual(pollCount, 1)

            poller.resume()

            XCTAssertEqual(pollCount, 2)
            XCTAssertEqual(scheduler.scheduleCount, 2)
            XCTAssertTrue(poller.isRunning)
            poller.pause()
        }
    }
}

@MainActor
private final class ManualPollingScheduler {
    private(set) var scheduleCount = 0
    private(set) var cancelCount = 0
    private(set) var interval: TimeInterval?
    private var tick: (@MainActor () -> Void)?

    func schedule(
        interval: TimeInterval,
        tick: @escaping @MainActor () -> Void
    ) -> TerminalContextPoller.Cancellation {
        scheduleCount += 1
        self.interval = interval
        self.tick = tick
        return { [weak self] in self?.cancelCount += 1 }
    }

    func fire() {
        tick?()
    }
}
