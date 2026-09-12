import AppKit
import SwiftTerm
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

    @MainActor
    func testTerminalCutRequiresTerminalResponderInDropdownPanel() {
        let panel = DropdownPanel()
        let terminal = TerminalView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        panel.contentView = terminal
        XCTAssertTrue(panel.makeFirstResponder(terminal))
        XCTAssertTrue(PanelInputRouting.terminalReceivingInput(in: panel) === terminal)

        let editor = NSTextView(frame: terminal.bounds)
        terminal.addSubview(editor)
        XCTAssertTrue(panel.makeFirstResponder(editor))
        XCTAssertNil(PanelInputRouting.terminalReceivingInput(in: panel))
    }

    @MainActor
    func testAuxiliaryWindowAndMissingWindowCannotRouteTerminalCut() {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let terminal = TerminalView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        window.contentView = terminal
        XCTAssertTrue(window.makeFirstResponder(terminal))

        XCTAssertNil(PanelInputRouting.terminalReceivingInput(in: window))
        XCTAssertNil(PanelInputRouting.terminalReceivingInput(in: nil))
        XCTAssertNil(PanelInputRouting.terminalReceivingInput(in: DropdownPanel()))
    }
}
