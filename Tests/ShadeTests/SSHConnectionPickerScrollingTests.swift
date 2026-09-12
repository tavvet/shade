import AppKit
import SwiftUI
import XCTest
@testable import Shade

@MainActor
final class SSHConnectionPickerScrollingTests: XCTestCase {
    func testFilteringKeepsSurvivingSelectedProfileVisible() throws {
        _ = NSApplication.shared
        let state = PickerScrollState()
        let host = NSHostingView(rootView: PickerScrollHarness(state: state))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 250),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        settle(host)

        state.selectedID = state.matches[18].id // prod19
        settle(host)
        let previousScrollView = try XCTUnwrap(findScrollView(in: host))
        XCTAssertGreaterThan(previousScrollView.documentVisibleRect.minY, 0)

        state.matches = SSHConnectionPickerSearch.matches(state.matches, query: "prod1")
        settle(host)

        let scrollView = try XCTUnwrap(findScrollView(in: host))
        XCTAssertFalse(scrollView === previousScrollView)
        XCTAssertEqual(state.selectedID, state.matches.last?.id)
        XCTAssertGreaterThan(scrollView.documentVisibleRect.minY, 0)
        let document = try XCTUnwrap(scrollView.documentView)
        XCTAssertEqual(scrollView.documentVisibleRect.maxY, document.bounds.maxY, accuracy: 2)
    }

    private func settle(_ view: NSView) {
        let deadline = Date().addingTimeInterval(0.2)
        repeat {
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        } while Date() < deadline
    }

    private func findScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView { return scrollView }
        for child in view.subviews {
            if let scrollView = findScrollView(in: child) { return scrollView }
        }
        return nil
    }
}

@MainActor
private final class PickerScrollState: ObservableObject {
    @Published var matches = (1...20).map { SSHProfile(name: String(format: "prod%02d", $0), host: "server") }
    @Published var selectedID: UUID?
}

private struct PickerScrollHarness: View {
    @ObservedObject var state: PickerScrollState

    var body: some View {
        SSHConnectionPickerList(matches: state.matches, selectedID: $state.selectedID,
                                quickSlot: { _ in nil }, onConnect: { _ in })
    }
}
