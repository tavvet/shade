import XCTest
@testable import Shade

@MainActor
final class GitRefreshCoordinatorTests: XCTestCase {
    // Generous default debounce — these tests still finish in milliseconds locally,
    // and the slack matters under load on CI runners.
    private let fastDebounce: Duration = .milliseconds(40)

    func testStrongReasonRefreshesAfterDebounce() async {
        let fetchCount = Counter()
        let applied = ResultBox<GitStatus?>()
        let coord = GitRefreshCoordinator(
            debounce: fastDebounce,
            weakReasonCooldown: 0,
            fetch: { _ in
                await fetchCount.increment()
                return .status(GitStatus(filesChanged: 3, insertions: 5, deletions: 2))
            },
            apply: { applied.set($0) }
        )
        coord.schedule(path: "/repo", reason: .cwdChanged)
        await waitForCount(fetchCount, equals: 1)

        XCTAssertEqual(applied.get(), GitStatus(filesChanged: 3, insertions: 5, deletions: 2))
    }

    func testRapidScheduleCallsCoalesceToSingleFetch() async {
        let fetchCount = Counter()
        let coord = GitRefreshCoordinator(
            debounce: fastDebounce,
            weakReasonCooldown: 0,
            fetch: { _ in
                await fetchCount.increment()
                return .status(.empty)
            },
            apply: { _ in }
        )
        coord.schedule(path: "/repo", reason: .cwdChanged)
        coord.schedule(path: "/repo", reason: .cwdChanged)
        coord.schedule(path: "/repo", reason: .cwdChanged)
        // Wait a generous buffer past the debounce, then verify only one fired.
        try? await Task.sleep(for: .milliseconds(400))

        let count = await fetchCount.value
        XCTAssertEqual(count, 1)
    }

    func testWeakReasonSkippedWithinCooldownAndSamePath() async {
        let fetchCount = Counter()
        let clock = TestClock()
        let coord = GitRefreshCoordinator(
            debounce: fastDebounce,
            weakReasonCooldown: 5,
            clock: clock.read,
            fetch: { _ in
                await fetchCount.increment()
                return .status(.empty)
            },
            apply: { _ in }
        )
        coord.schedule(path: "/repo", reason: .cwdChanged)
        await waitForCount(fetchCount, equals: 1)

        // 2 seconds later (< 5s cooldown), weak reason on same path: should skip.
        clock.advance(by: 2)
        coord.schedule(path: "/repo", reason: .tabActivated)
        try? await Task.sleep(for: .milliseconds(400))

        let count = await fetchCount.value
        XCTAssertEqual(count, 1)
    }

    func testFallbackPollIsSkippedWithinCooldownAndSamePath() async {
        let fetchCount = Counter()
        let clock = TestClock()
        let coord = GitRefreshCoordinator(
            debounce: fastDebounce,
            weakReasonCooldown: 5,
            clock: clock.read,
            fetch: { _ in
                await fetchCount.increment()
                return .status(.empty)
            },
            apply: { _ in }
        )
        coord.schedule(path: "/repo", reason: .cwdChanged)
        await waitForCount(fetchCount, equals: 1)

        clock.advance(by: 2)
        coord.schedule(path: "/repo", reason: .fallbackPoll)
        try? await Task.sleep(for: .milliseconds(400))

        let count = await fetchCount.value
        XCTAssertEqual(count, 1)
    }

    func testWeakReasonPassesAfterCooldownExpires() async {
        let fetchCount = Counter()
        let clock = TestClock()
        let coord = GitRefreshCoordinator(
            debounce: fastDebounce,
            weakReasonCooldown: 5,
            clock: clock.read,
            fetch: { _ in
                await fetchCount.increment()
                return .status(.empty)
            },
            apply: { _ in }
        )
        coord.schedule(path: "/repo", reason: .cwdChanged)
        await waitForCount(fetchCount, equals: 1)

        // 10 seconds later (> 5s cooldown), weak reason on same path: fires.
        clock.advance(by: 10)
        coord.schedule(path: "/repo", reason: .focusReturned)
        await waitForCount(fetchCount, equals: 2)
    }

    func testWeakReasonPassesOnDifferentPathEvenWithinCooldown() async {
        let fetchCount = Counter()
        let clock = TestClock()
        let coord = GitRefreshCoordinator(
            debounce: fastDebounce,
            weakReasonCooldown: 5,
            clock: clock.read,
            fetch: { _ in
                await fetchCount.increment()
                return .status(.empty)
            },
            apply: { _ in }
        )
        coord.schedule(path: "/repo-a", reason: .cwdChanged)
        await waitForCount(fetchCount, equals: 1)

        // 1 second later, weak reason on DIFFERENT path: fires.
        clock.advance(by: 1)
        coord.schedule(path: "/repo-b", reason: .tabActivated)
        await waitForCount(fetchCount, equals: 2)
    }

    func testStrongReasonAlwaysFiresEvenWithinCooldown() async {
        let fetchCount = Counter()
        let clock = TestClock()
        let coord = GitRefreshCoordinator(
            debounce: fastDebounce,
            weakReasonCooldown: 60,
            clock: clock.read,
            fetch: { _ in
                await fetchCount.increment()
                return .status(.empty)
            },
            apply: { _ in }
        )
        coord.schedule(path: "/repo", reason: .cwdChanged)
        await waitForCount(fetchCount, equals: 1)

        // 1 second later (well within cooldown), strong reason: fires.
        clock.advance(by: 1)
        coord.schedule(path: "/repo", reason: .commandFinished)
        await waitForCount(fetchCount, equals: 2)
    }

    func testCancelPreventsPendingRefresh() async {
        let fetchCount = Counter()
        let coord = GitRefreshCoordinator(
            debounce: .milliseconds(150),
            weakReasonCooldown: 0,
            fetch: { _ in
                await fetchCount.increment()
                return .status(.empty)
            },
            apply: { _ in }
        )
        coord.schedule(path: "/repo", reason: .cwdChanged)
        // Cancel before debounce elapses.
        try? await Task.sleep(for: .milliseconds(40))
        coord.cancel()
        try? await Task.sleep(for: .milliseconds(400))

        let count = await fetchCount.value
        XCTAssertEqual(count, 0)
    }

    func testCancelPreventsInFlightRefreshApply() async {
        let fetchCount = Counter()
        let applyCount = ApplyCounter()
        let coord = GitRefreshCoordinator(
            debounce: fastDebounce,
            weakReasonCooldown: 0,
            fetch: { _ in
                await fetchCount.increment()
                try? await Task.sleep(for: .milliseconds(500))
                return .status(GitStatus(filesChanged: 1, insertions: 0, deletions: 0))
            },
            apply: { _ in applyCount.increment() }
        )
        coord.schedule(path: "/repo", reason: .cwdChanged)
        await waitForCount(fetchCount, equals: 1)

        coord.cancel()
        try? await Task.sleep(for: .milliseconds(700))

        XCTAssertEqual(applyCount.value, 0)
    }

    func testCancelClearsCooldownState() async {
        let fetchCount = Counter()
        let clock = TestClock()
        let coord = GitRefreshCoordinator(
            debounce: fastDebounce,
            weakReasonCooldown: 60,
            clock: clock.read,
            fetch: { _ in
                await fetchCount.increment()
                return .status(.empty)
            },
            apply: { _ in }
        )
        coord.schedule(path: "/repo", reason: .cwdChanged)
        await waitForCount(fetchCount, equals: 1)

        coord.cancel()
        // After cancel, a weak reason should fire again because state is cleared.
        coord.schedule(path: "/repo", reason: .tabActivated)
        await waitForCount(fetchCount, equals: 2)
    }

    func testFailedRefreshPreservesLastStatusAndDoesNotStartCooldown() async {
        let fetchCount = Counter()
        let clock = TestClock()
        let applied = StatusApplyRecorder()
        let dirty = GitStatus(filesChanged: 2, insertions: 4, deletions: 1)
        let coord = GitRefreshCoordinator(
            debounce: fastDebounce,
            weakReasonCooldown: 5,
            clock: clock.read,
            fetch: { _ in
                switch await fetchCount.increment() {
                case 1: return .status(dirty)
                case 2: return .failed
                default: return .status(.empty)
                }
            },
            apply: { applied.append($0) }
        )

        coord.schedule(path: "/repo", reason: .cwdChanged)
        await waitForApplyCount(applied, equals: 1)
        clock.advance(by: 1)

        coord.schedule(path: "/repo", reason: .commandFinished)
        await waitForCount(fetchCount, equals: 2)
        try? await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(applied.values, [dirty])

        // A failed strong refresh must not rate-limit this immediate weak retry.
        coord.schedule(path: "/repo", reason: .focusReturned)
        await waitForApplyCount(applied, equals: 2)
        XCTAssertEqual(applied.values, [dirty, .empty])
    }

    func testConfirmedNonRepositoryClearsStatus() async {
        let applied = StatusApplyRecorder()
        let coord = GitRefreshCoordinator(
            debounce: fastDebounce,
            weakReasonCooldown: 0,
            fetch: { _ in .notRepository },
            apply: { applied.append($0) }
        )

        coord.schedule(path: "/outside-repo", reason: .cwdChanged)
        await waitForApplyCount(applied, equals: 1)

        XCTAssertEqual(applied.values.count, 1)
        XCTAssertNil(applied.values[0])
    }

    // MARK: - Helpers

    /// Polls the counter until it hits `expected` or the timeout elapses.
    /// Fails the test instead of hanging if the count never reaches it.
    private func waitForCount(
        _ counter: Counter,
        equals expected: Int,
        timeout: TimeInterval = 3.0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let value = await counter.value
            if value == expected { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
        let final = await counter.value
        XCTFail(
            "Expected fetch count \(expected) within \(timeout)s, got \(final)",
            file: file, line: line)
    }

    private func waitForApplyCount(
        _ recorder: StatusApplyRecorder,
        equals expected: Int,
        timeout: TimeInterval = 3.0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if recorder.values.count == expected { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTFail(
            "Expected apply count \(expected) within \(timeout)s, got \(recorder.values.count)",
            file: file, line: line)
    }
}

// MARK: - Test fixtures

/// Sendable counter so tests can observe how often the injected fetcher ran
/// from off-main detached tasks.
private actor Counter {
    private(set) var value: Int = 0
    @discardableResult
    func increment() -> Int {
        value += 1
        return value
    }
}

/// Captures the last applied value from a `@MainActor` apply closure.
@MainActor
private final class ResultBox<T> {
    private var stored: T?
    func set(_ value: T) { stored = value }
    func get() -> T? { stored }
}

@MainActor
private final class ApplyCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}

@MainActor
private final class StatusApplyRecorder {
    private(set) var values: [GitStatus?] = []
    func append(_ status: GitStatus?) { values.append(status) }
}

/// Class-based virtual clock — passes a method reference into the
/// coordinator instead of capturing a mutable variable in a closure (the
/// latter quietly misbehaves under strict-concurrency toolchains).
@MainActor
private final class TestClock {
    private var current: Date = Date(timeIntervalSince1970: 0)

    func read() -> Date { current }
    func advance(by seconds: TimeInterval) {
        current = current.addingTimeInterval(seconds)
    }
}
