import SwiftTerm
import XCTest
@testable import Shade

final class TerminalDelegateProxyTests: XCTestCase {
    @MainActor
    func testHandledVisualBellSuppressesForwardedAudibleBell() {
        let forward = BellRecordingDelegate()
        let proxy = TerminalDelegateProxy(forward: forward)
        proxy.onBell = { true }

        proxy.bell(source: ActivityTerminalView(frame: .zero))

        XCTAssertEqual(forward.bellCount, 0)
    }

    @MainActor
    func testUnhandledBellUsesForwardDelegate() {
        let forward = BellRecordingDelegate()
        let proxy = TerminalDelegateProxy(forward: forward)
        proxy.onBell = { false }

        proxy.bell(source: ActivityTerminalView(frame: .zero))

        XCTAssertEqual(forward.bellCount, 1)
    }
}

private final class BellRecordingDelegate: TerminalViewDelegate {
    var bellCount = 0

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func send(source: TerminalView, data: ArraySlice<UInt8>) {}
    func scrolled(source: TerminalView, position: Double) {}

    func bell(source: TerminalView) {
        bellCount += 1
    }

    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}
