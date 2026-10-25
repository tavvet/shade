import XCTest
@testable import Shade

@MainActor
final class PreferencesChangeAnnouncerTests: XCTestCase {
    func testFirstRequestIsPostedAfterTheCallerReturnsWithoutWaiting() async {
        var posts = 0
        let announcer = PreferencesChangeAnnouncer(interval: .seconds(10)) { posts += 1 }

        announcer.request()
        XCTAssertEqual(posts, 0, "posted inside the caller's transaction")
        let started = ContinuousClock.now
        await announcer.waitForPending()

        XCTAssertEqual(posts, 1)
        XCTAssertLessThan(started.duration(to: .now), .seconds(1))
    }

    func testRequestsBeforeThePostAreCoalesced() async {
        var posts = 0
        let announcer = PreferencesChangeAnnouncer(interval: .milliseconds(50)) { posts += 1 }

        for _ in 0..<10 { announcer.request() }
        await announcer.waitForPending()

        XCTAssertEqual(posts, 1)
    }

    func testBurstPostsAreSpacedByTheInterval() async {
        var postTimes: [ContinuousClock.Instant] = []
        let announcer = PreferencesChangeAnnouncer(interval: .milliseconds(80)) {
            postTimes.append(.now)
        }

        announcer.request()
        await announcer.waitForPending()
        announcer.request()
        await announcer.waitForPending()

        XCTAssertEqual(postTimes.count, 2)
        XCTAssertGreaterThanOrEqual(postTimes[0].duration(to: postTimes[1]), .milliseconds(75))
    }
}
