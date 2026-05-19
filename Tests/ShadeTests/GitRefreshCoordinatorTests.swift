import XCTest
@testable import Shade

@MainActor
final class GitRefreshCoordinatorTests: XCTestCase {
    // Short debounce keeps tests fast while still exercising the timer path.
    private let fastDebounce: Duration = .milliseconds(20)

    func testStrongReasonRefreshesAfterDebounce() async {
        let fetchCount = Counter()
        let applied = ResultBox<GitStatus?>()
        let coord = GitRefreshCoordinator(
            debounce: fastDebounce,
            weakReasonCooldown: 0,
            fetch: { _ in
                await fetchCount.increment()
                return GitStatus(filesChanged: 3, insertions: 5, deletions: 2)
            },
            apply: { applied.set($0) }
        )
        coord.schedule(path: "/repo", reason: .cwdChanged)
        try? await Task.sleep(for: .milliseconds(80))

        let count = await fetchCount.value
        XCTAssertEqual(count, 1)
        XCTAssertEqual(applied.get(), GitStatus(filesChanged: 3, insertions: 5, deletions: 2))
    }

    func testRapidScheduleCallsCoalesceToSingleFetch() async {
        let fetchCount = Counter()
        let coord = GitRefreshCoordinator(
            debounce: fastDebounce,
            weakReasonCooldown: 0,
            fetch: { _ in
                await fetchCount.increment()
                return nil
            },
            apply: { _ in }
        )
        coord.schedule(path: "/repo", reason: .cwdChanged)
        coord.schedule(path: "/repo", reason: .cwdChanged)
        coord.schedule(path: "/repo", reason: .cwdChanged)
        try? await Task.sleep(for: .milliseconds(80))

        let count = await fetchCount.value
        XCTAssertEqual(count, 1)
    }

    func testWeakReasonSkippedWithinCooldownAndSamePath() async {
        let fetchCount = Counter()
        var now = Date(timeIntervalSince1970: 0)
        let coord = GitRefreshCoordinator(
            debounce: fastDebounce,
            weakReasonCooldown: 5,
            clock: { now },
            fetch: { _ in
                await fetchCount.increment()
                return nil
            },
            apply: { _ in }
        )
        coord.schedule(path: "/repo", reason: .cwdChanged)
        try? await Task.sleep(for: .milliseconds(80))
        let firstCount = await fetchCount.value
        XCTAssertEqual(firstCount, 1)

        // 2 seconds later (< 5s cooldown), weak reason on same path: skip.
        now = Date(timeIntervalSince1970: 2)
        coord.schedule(path: "/repo", reason: .tabActivated)
        try? await Task.sleep(for: .milliseconds(80))
        let secondCount = await fetchCount.value
        XCTAssertEqual(secondCount, 1)
    }

    func testWeakReasonPassesAfterCooldownExpires() async {
        let fetchCount = Counter()
        var now = Date(timeIntervalSince1970: 0)
        let coord = GitRefreshCoordinator(
            debounce: fastDebounce,
            weakReasonCooldown: 5,
            clock: { now },
            fetch: { _ in
                await fetchCount.increment()
                return nil
            },
            apply: { _ in }
        )
        coord.schedule(path: "/repo", reason: .cwdChanged)
        try? await Task.sleep(for: .milliseconds(80))
        let firstCount = await fetchCount.value
        XCTAssertEqual(firstCount, 1)

        // 10 seconds later (> 5s cooldown), weak reason on same path: fires.
        now = Date(timeIntervalSince1970: 10)
        coord.schedule(path: "/repo", reason: .focusReturned)
        try? await Task.sleep(for: .milliseconds(80))
        let secondCount = await fetchCount.value
        XCTAssertEqual(secondCount, 2)
    }

    func testWeakReasonPassesOnDifferentPathEvenWithinCooldown() async {
        let fetchCount = Counter()
        var now = Date(timeIntervalSince1970: 0)
        let coord = GitRefreshCoordinator(
            debounce: fastDebounce,
            weakReasonCooldown: 5,
            clock: { now },
            fetch: { _ in
                await fetchCount.increment()
                return nil
            },
            apply: { _ in }
        )
        coord.schedule(path: "/repo-a", reason: .cwdChanged)
        try? await Task.sleep(for: .milliseconds(80))
        let firstCount = await fetchCount.value
        XCTAssertEqual(firstCount, 1)

        // 1 second later, weak reason on DIFFERENT path: fires.
        now = Date(timeIntervalSince1970: 1)
        coord.schedule(path: "/repo-b", reason: .tabActivated)
        try? await Task.sleep(for: .milliseconds(80))
        let secondCount = await fetchCount.value
        XCTAssertEqual(secondCount, 2)
    }

    func testStrongReasonAlwaysFiresEvenWithinCooldown() async {
        let fetchCount = Counter()
        var now = Date(timeIntervalSince1970: 0)
        let coord = GitRefreshCoordinator(
            debounce: fastDebounce,
            weakReasonCooldown: 60,
            clock: { now },
            fetch: { _ in
                await fetchCount.increment()
                return nil
            },
            apply: { _ in }
        )
        coord.schedule(path: "/repo", reason: .cwdChanged)
        try? await Task.sleep(for: .milliseconds(80))
        let firstCount = await fetchCount.value
        XCTAssertEqual(firstCount, 1)

        // 1 second later (well within cooldown), strong reason: fires.
        now = Date(timeIntervalSince1970: 1)
        coord.schedule(path: "/repo", reason: .commandFinished)
        try? await Task.sleep(for: .milliseconds(80))
        let secondCount = await fetchCount.value
        XCTAssertEqual(secondCount, 2)
    }

    func testCancelPreventsPendingRefresh() async {
        let fetchCount = Counter()
        let coord = GitRefreshCoordinator(
            debounce: .milliseconds(100),
            weakReasonCooldown: 0,
            fetch: { _ in
                await fetchCount.increment()
                return nil
            },
            apply: { _ in }
        )
        coord.schedule(path: "/repo", reason: .cwdChanged)
        // Cancel before debounce elapses.
        try? await Task.sleep(for: .milliseconds(20))
        coord.cancel()
        try? await Task.sleep(for: .milliseconds(150))

        let count = await fetchCount.value
        XCTAssertEqual(count, 0)
    }

    func testCancelClearsCooldownState() async {
        let fetchCount = Counter()
        var now = Date(timeIntervalSince1970: 0)
        let coord = GitRefreshCoordinator(
            debounce: fastDebounce,
            weakReasonCooldown: 60,
            clock: { now },
            fetch: { _ in
                await fetchCount.increment()
                return nil
            },
            apply: { _ in }
        )
        coord.schedule(path: "/repo", reason: .cwdChanged)
        try? await Task.sleep(for: .milliseconds(80))
        let firstCount = await fetchCount.value
        XCTAssertEqual(firstCount, 1)

        coord.cancel()
        // After cancel, weak reason should fire again because state is cleared.
        coord.schedule(path: "/repo", reason: .tabActivated)
        try? await Task.sleep(for: .milliseconds(80))
        let secondCount = await fetchCount.value
        XCTAssertEqual(secondCount, 2)
    }
}

// MARK: - Test helpers

/// Sendable counter so tests can observe how often the injected fetcher ran
/// from off-main detached tasks.
private actor Counter {
    private(set) var value: Int = 0
    func increment() { value += 1 }
}

/// Apply closures fire on @MainActor — this captures the last applied value
/// without needing locking.
@MainActor
private final class ResultBox<T> {
    private var stored: T?
    func set(_ value: T) { stored = value }
    func get() -> T? { stored }
}
