import AppKit
import XCTest
@testable import Shade

@MainActor
final class ClickEventTests: XCTestCase {
    func testRecognizesOnlyTheSecondLeftMouseClick() throws {
        XCTAssertFalse(ClickEvent.isDoubleClick(
            try mouseEvent(type: .leftMouseUp, clickCount: 1)
        ))
        XCTAssertTrue(ClickEvent.isDoubleClick(
            try mouseEvent(type: .leftMouseUp, clickCount: 2)
        ))
        XCTAssertFalse(ClickEvent.isDoubleClick(
            try mouseEvent(type: .leftMouseUp, clickCount: 3)
        ))
    }

    func testRecognizesEveryClickAfterTheFirstAsRepeated() throws {
        XCTAssertFalse(ClickEvent.isRepeatedClick(
            try mouseEvent(type: .leftMouseUp, clickCount: 1)
        ))
        XCTAssertTrue(ClickEvent.isRepeatedClick(
            try mouseEvent(type: .leftMouseUp, clickCount: 2)
        ))
        XCTAssertTrue(ClickEvent.isRepeatedClick(
            try mouseEvent(type: .leftMouseDown, clickCount: 3)
        ))
        XCTAssertFalse(ClickEvent.isRepeatedClick(nil))
        XCTAssertFalse(ClickEvent.isRepeatedClick(
            try mouseEvent(type: .rightMouseUp, clickCount: 2)
        ))
        XCTAssertFalse(ClickEvent.isRepeatedClick(try keyEvent()))
    }

    func testRejectsMissingAndNonLeftMouseEvents() throws {
        XCTAssertFalse(ClickEvent.isDoubleClick(nil))
        XCTAssertFalse(ClickEvent.isDoubleClick(
            try mouseEvent(type: .rightMouseUp, clickCount: 2)
        ))
        XCTAssertFalse(ClickEvent.isDoubleClick(try keyEvent()))
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
