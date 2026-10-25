import XCTest
@testable import Shade
@testable import ShadeCore

@MainActor
final class TabsObservableTests: XCTestCase {
    func testControllerDoesNotKeepReleasedObservableAlive() {
        let controller = TerminalsController(preferences: StaticPreferences())
        let remaining = TabsObservable(controller: controller)
        weak var released: TabsObservable?

        do {
            let value = TabsObservable(controller: controller)
            released = value
        }
        XCTAssertNil(released)

        // The dropped observer does not disturb the one that is still alive.
        let session = controller.newSession(configuration: .waitingForTermination)
        defer { stop([session]) }
        XCTAssertEqual(remaining.tabs.map(\.id), [session.id])
    }

    func testSeveralObserversOfOneControllerAllReceiveChanges() {
        let controller = TerminalsController(preferences: StaticPreferences())
        let first = TabsObservable(controller: controller)
        let second = TabsObservable(controller: controller)

        let session = controller.newSession(configuration: .waitingForTermination)
        defer { stop([session]) }
        controller.renameSession(at: 0, to: "Shared")

        XCTAssertEqual(first.tabs.first?.label, "1 · Shared")
        XCTAssertEqual(second.tabs.first?.label, "1 · Shared")
    }

    func testBackgroundOutputShowsTheActivityDot() {
        let controller = TerminalsController(preferences: StaticPreferences())
        let observable = TabsObservable(controller: controller)
        let background = controller.newSession(configuration: command("sleep 0.3; printf output; sleep 30"))
        let foreground = controller.newSession(configuration: .waitingForTermination)
        defer { stop([background, foreground]) }

        XCTAssertEqual(observable.tabs.first?.indicator, TabIndicator.none)
        waitForCondition { observable.tabs.first?.indicator == .activity }
        XCTAssertEqual(observable.tabs.last?.indicator, TabIndicator.none)
    }

    func testFailedCommandShowsTheFailureDotAndReachesTheCommandCallback() {
        let controller = TerminalsController(preferences: StaticPreferences())
        let observable = TabsObservable(controller: controller)
        var finishedExitCodes: [Int?] = []
        controller.onCommandFinish = { _, exitCode, _ in finishedExitCodes.append(exitCode) }
        let session = controller.newSession(configuration: command(
            "sleep 0.2; printf '\\033]133;C\\007\\033]133;D;1\\007'; sleep 30"
        ))
        defer { stop([session]) }

        waitForCondition { observable.tabs.first?.indicator == .failed }
        XCTAssertEqual(finishedExitCodes, [1])
    }

    func testTabSetSelectionAndRenameReachTheObservableDirectly() {
        let controller = TerminalsController(preferences: StaticPreferences())
        let observable = TabsObservable(controller: controller)
        let first = controller.newSession(configuration: .waitingForTermination)
        let second = controller.newSession(configuration: .waitingForTermination)
        defer { stop([first, second]) }

        XCTAssertEqual(observable.tabs.map(\.id), [first.id, second.id])
        XCTAssertEqual(observable.activeIndex, 1)

        controller.select(at: 0)
        XCTAssertEqual(observable.activeIndex, 0)

        controller.renameSession(at: 1, to: "Production")
        XCTAssertEqual(observable.tabs[1].label, "2 · Production")
        XCTAssertEqual(observable.tabs[1].editableName, "Production")
    }

    private func command(_ script: String) -> TerminalLaunchConfiguration {
        TerminalLaunchConfiguration(
            initialCommand: ProcessInvocation(executable: "/bin/sh", arguments: ["-c", script])
        )
    }

    private func stop(_ sessions: [TerminalSession]) {
        for session in sessions {
            session.onExit = nil
            session.terminate()
        }
    }

    func testTabBarScrollingStaysDisabledUntilViewportIsMeasured() {
        XCTAssertFalse(TabBarLayout.needsHorizontalScrolling(
            contentWidth: 200,
            viewportWidth: 0
        ))
    }

    func testTabBarScrollingStaysDisabledWhenContentFits() {
        XCTAssertFalse(TabBarLayout.needsHorizontalScrolling(
            contentWidth: 199,
            viewportWidth: 200
        ))
        XCTAssertFalse(TabBarLayout.needsHorizontalScrolling(
            contentWidth: 200.5,
            viewportWidth: 200
        ))
    }

    func testTabBarScrollingTurnsOnForRealOverflow() {
        XCTAssertTrue(TabBarLayout.needsHorizontalScrolling(
            contentWidth: 202,
            viewportWidth: 200
        ))
    }

    func testFormatLabelUsesIndexAloneWhenTitleEmpty() {
        XCTAssertEqual(TabsObservable.formatLabel(index: 0, title: ""), "1")
        XCTAssertEqual(TabsObservable.formatLabel(index: 4, title: "   "), "5")
    }

    func testFormatLabelJoinsIndexAndTitle() {
        XCTAssertEqual(TabsObservable.formatLabel(index: 1, title: "zsh"), "2 · zsh")
    }

    func testFormatLabelTruncatesLongTitlesFromTheLeft() {
        let long = String(repeating: "x", count: 40)
        let result = TabsObservable.formatLabel(index: 0, title: long)
        XCTAssertTrue(result.hasPrefix("1 · …"))
        // Visible suffix of the original should still be present.
        XCTAssertTrue(result.contains(String(repeating: "x", count: 24)))
    }

    func testIndicatorIsNoneWhenIdleOrSuccessful() {
        XCTAssertEqual(TabsObservable.indicator(lastExitCode: nil, hasUnseenActivity: false), .none)
        XCTAssertEqual(TabsObservable.indicator(lastExitCode: 0, hasUnseenActivity: false), .none)
    }

    func testIndicatorIsActivityForUnseenOutput() {
        XCTAssertEqual(TabsObservable.indicator(lastExitCode: nil, hasUnseenActivity: true), .activity)
        XCTAssertEqual(TabsObservable.indicator(lastExitCode: 0, hasUnseenActivity: true), .activity)
    }

    func testIndicatorIsFailedForNonZeroExit() {
        XCTAssertEqual(TabsObservable.indicator(lastExitCode: 1, hasUnseenActivity: false), .failed)
    }

    func testIndicatorFailureWinsOverActivity() {
        XCTAssertEqual(TabsObservable.indicator(lastExitCode: 127, hasUnseenActivity: true), .failed)
    }
}
