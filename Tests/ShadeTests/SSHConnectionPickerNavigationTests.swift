import AppKit
import XCTest
@testable import Shade

@MainActor
final class SSHConnectionPickerNavigationTests: XCTestCase {
    func testPanelRoutesPlainArrowKeysToSelection() throws {
        let panel = SSHConnectionPickerPanel(contentViewController: NSViewController())
        var directions: [SSHConnectionPickerSelectionDirection] = []
        panel.onMoveSelection = { directions.append($0) }

        panel.sendEvent(try arrowEvent(keyCode: KeyCodes.downArrow))
        panel.sendEvent(try arrowEvent(keyCode: KeyCodes.upArrow))

        XCTAssertEqual(directions, [.down, .up])
    }

    func testArrowRoutingIgnoresSystemFlags() {
        XCTAssertEqual(
            SSHConnectionPickerKeyNavigation.direction(
                keyCode: KeyCodes.upArrow,
                modifierFlags: [.function, .numericPad],
                hasMarkedText: false
            ),
            .up
        )
    }

    func testArrowRoutingRejectsUserModifiers() {
        for modifier: NSEvent.ModifierFlags in [.command, .control, .option, .shift] {
            XCTAssertNil(
                SSHConnectionPickerKeyNavigation.direction(
                    keyCode: KeyCodes.downArrow,
                    modifierFlags: [modifier, .function, .numericPad],
                    hasMarkedText: false
                )
            )
        }
    }

    func testArrowRoutingDefersToTextInputWithMarkedText() {
        XCTAssertNil(
            SSHConnectionPickerKeyNavigation.direction(
                keyCode: KeyCodes.downArrow,
                modifierFlags: [.function, .numericPad],
                hasMarkedText: true
            )
        )
    }

    func testSelectionMovesAndStopsAtListBounds() {
        let ids = [1, 2, 3]

        XCTAssertEqual(moved(in: ids, from: 1, direction: .up), 1)
        XCTAssertEqual(moved(in: ids, from: 1, direction: .down), 2)
        XCTAssertEqual(moved(in: ids, from: 2, direction: .down), 3)
        XCTAssertEqual(moved(in: ids, from: 3, direction: .down), 3)
    }

    func testSelectionRecoversFromMissingSelection() {
        let ids = [1, 2, 3]

        XCTAssertEqual(moved(in: ids, from: nil, direction: .down), 1)
        XCTAssertEqual(moved(in: ids, from: nil, direction: .up), 3)
        XCTAssertEqual(moved(in: ids, from: 99, direction: .down), 1)
        XCTAssertNil(moved(in: [], from: nil, direction: .down))
    }

    private func moved(
        in ids: [Int],
        from selectedID: Int?,
        direction: SSHConnectionPickerSelectionDirection
    ) -> Int? {
        SSHConnectionPickerSelection.movedID(
            in: ids,
            from: selectedID,
            direction: direction
        )
    }

    private func arrowEvent(keyCode: UInt16) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.function, .numericPad],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        ))
    }
}
