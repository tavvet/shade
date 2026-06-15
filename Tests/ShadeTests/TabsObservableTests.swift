import XCTest
@testable import Shade

@MainActor
final class TabsObservableTests: XCTestCase {
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
