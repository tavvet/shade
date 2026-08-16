import AppKit
import XCTest
@testable import Shade

final class SSHConnectionPickerLayoutTests: XCTestCase {
    func testSmallParentExpandsAroundItsTopCenter() {
        let visible = NSRect(x: 0, y: 0, width: 1_440, height: 900)
        let parent = NSRect(x: 640, y: 810, width: 160, height: 90)

        let frame = SSHConnectionPickerLayout.frame(
            parentFrame: parent,
            visibleFrame: visible
        )

        XCTAssertEqual(frame.width, SSHConnectionPickerLayout.minimumWidth)
        XCTAssertEqual(frame.height, SSHConnectionPickerLayout.minimumHeight)
        XCTAssertGreaterThanOrEqual(frame.height, 520)
        XCTAssertEqual(frame.midX, parent.midX)
        XCTAssertEqual(frame.maxY, parent.maxY)
    }

    func testExpandedFrameIsClampedToVisibleScreenEdges() {
        let visible = NSRect(x: 100, y: 50, width: 1_000, height: 700)
        let parent = NSRect(x: 1_050, y: 650, width: 50, height: 100)

        let frame = SSHConnectionPickerLayout.frame(
            parentFrame: parent,
            visibleFrame: visible
        )

        XCTAssertEqual(frame.maxX, visible.maxX)
        XCTAssertLessThanOrEqual(frame.maxY, visible.maxY)
        XCTAssertGreaterThanOrEqual(frame.minY, visible.minY)
    }

    func testVisibleScreenBoundsWinWhenTheyAreBelowMinimumSize() {
        let visible = NSRect(x: 10, y: 20, width: 400, height: 300)
        let parent = NSRect(x: 10, y: 220, width: 400, height: 100)

        XCTAssertEqual(
            SSHConnectionPickerLayout.frame(
                parentFrame: parent,
                visibleFrame: visible
            ),
            visible
        )
    }
}
