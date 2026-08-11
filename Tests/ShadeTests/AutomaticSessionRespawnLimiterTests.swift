import XCTest
@testable import Shade

final class AutomaticSessionRespawnLimiterTests: XCTestCase {
    func testAllowsOnlyOneAutomaticRespawnWithoutUserInput() {
        var limiter = AutomaticSessionRespawnLimiter()

        XCTAssertTrue(limiter.shouldAllowRespawn())
        XCTAssertFalse(limiter.shouldAllowRespawn())
        XCTAssertFalse(limiter.shouldAllowRespawn())
    }

    func testUserInputResetAllowsAnotherAutomaticRespawn() {
        var limiter = AutomaticSessionRespawnLimiter()

        XCTAssertTrue(limiter.shouldAllowRespawn())
        limiter.reset()

        XCTAssertTrue(limiter.shouldAllowRespawn())
    }
}
