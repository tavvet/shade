import AppKit
import XCTest
@testable import Shade

@MainActor
final class ConnectionsSettingsClickEventTests: XCTestCase {
    func testRecognizesOnlyTheSecondLeftMouseClick() throws {
        XCTAssertFalse(ConnectionsSettingsClickEvent.isDoubleClick(
            try mouseEvent(type: .leftMouseUp, clickCount: 1)
        ))
        XCTAssertTrue(ConnectionsSettingsClickEvent.isDoubleClick(
            try mouseEvent(type: .leftMouseUp, clickCount: 2)
        ))
        XCTAssertFalse(ConnectionsSettingsClickEvent.isDoubleClick(
            try mouseEvent(type: .leftMouseUp, clickCount: 3)
        ))
    }

    func testRejectsMissingAndNonLeftMouseEvents() throws {
        XCTAssertFalse(ConnectionsSettingsClickEvent.isDoubleClick(nil))
        XCTAssertFalse(ConnectionsSettingsClickEvent.isDoubleClick(
            try mouseEvent(type: .rightMouseUp, clickCount: 2)
        ))
        XCTAssertFalse(ConnectionsSettingsClickEvent.isDoubleClick(try keyEvent()))
    }

    private func mouseEvent(
        type: NSEvent.EventType,
        clickCount: Int
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: type,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: clickCount,
            pressure: 0
        ))
    }

    private func keyEvent() throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "a",
            charactersIgnoringModifiers: "a",
            isARepeat: false,
            keyCode: 0
        ))
    }
}
