import AppKit
import XCTest
@testable import Shade

final class TerminalViewHostTests: XCTestCase {
    func testShowReplacesContentAndPinsItToEveryEdge() async {
        await MainActor.run {
            let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
            let host = TerminalViewHost(containerView: container)
            let first = NSView()
            let second = NSView()

            host.show(first)
            host.show(second)

            XCTAssertNil(first.superview)
            XCTAssertEqual(container.subviews, [second])
            XCTAssertEqual(second.frame, container.bounds)

            let edgeConstraints = container.constraints.filter {
                $0.firstItem === second || $0.secondItem === second
            }
            XCTAssertEqual(edgeConstraints.count, 4)
        }
    }

    func testFocusMakesHostedViewFirstResponder() async {
        await MainActor.run {
            let host = TerminalViewHost()
            let terminalView = FirstResponderView()
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 180),
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.contentView = host.containerView
            host.show(terminalView)

            host.focus(terminalView)

            XCTAssertTrue(window.firstResponder === terminalView)
        }
    }
}

private final class FirstResponderView: NSView {
    override var acceptsFirstResponder: Bool { true }
}
