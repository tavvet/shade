import AppKit
import XCTest
@testable import Shade

final class PanelInputRoutingTests: XCTestCase {
    @MainActor
    func testTextEditorKeepsKeyboardInputOnResponderChain() {
        XCTAssertTrue(PanelInputRouting.isEditingText(NSTextView()))
    }

    @MainActor
    func testTerminalLikeViewKeepsCustomInputRouting() {
        XCTAssertFalse(PanelInputRouting.isEditingText(NSView()))
        XCTAssertFalse(PanelInputRouting.isEditingText(nil))
    }
}
