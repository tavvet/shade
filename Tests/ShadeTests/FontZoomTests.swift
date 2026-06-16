import XCTest
@testable import Shade

final class FontZoomTests: XCTestCase {
    func testZoomInAddsAStep() {
        XCTAssertEqual(Preferences.zoomedFontSize(from: 13, delta: 1), 14)
    }

    func testZoomOutSubtractsAStep() {
        XCTAssertEqual(Preferences.zoomedFontSize(from: 13, delta: -1), 12)
    }

    func testZoomInClampsAtMax() {
        XCTAssertEqual(Preferences.zoomedFontSize(from: 32, delta: 1), Preferences.maxFontSize)
        XCTAssertEqual(Preferences.zoomedFontSize(from: 31, delta: 5), Preferences.maxFontSize)
    }

    func testZoomOutClampsAtMin() {
        XCTAssertEqual(Preferences.zoomedFontSize(from: 8, delta: -1), Preferences.minFontSize)
        XCTAssertEqual(Preferences.zoomedFontSize(from: 9, delta: -5), Preferences.minFontSize)
    }

    func testResetReturnsDefault() {
        XCTAssertEqual(Preferences.zoomedFontSize(from: 20, delta: nil), Preferences.defaults.fontSize)
    }

    func testClampBounds() {
        XCTAssertEqual(Preferences.clampFontSize(4), Preferences.minFontSize)
        XCTAssertEqual(Preferences.clampFontSize(99), Preferences.maxFontSize)
        XCTAssertEqual(Preferences.clampFontSize(15), 15)
    }
}
