import XCTest
import AppKit
@testable import Shade

final class PreferencesTests: XCTestCase {
    private func freshStore() -> UserDefaults {
        let suite = "ShadeTests-" + UUID().uuidString
        return UserDefaults(suiteName: suite)!
    }

    func testLoadReturnsDefaultsWhenStoreIsEmpty() {
        let prefs = Preferences.load(from: freshStore())
        XCTAssertEqual(prefs.widthFraction, Preferences.defaults.widthFraction)
        XCTAssertEqual(prefs.heightFraction, Preferences.defaults.heightFraction)
        XCTAssertEqual(prefs.horizontalAlignment, .center)
        XCTAssertEqual(prefs.screenChoice, .mouseLocation)
        XCTAssertEqual(prefs.fontName, "")
        XCTAssertEqual(prefs.backgroundOpacity, 0.94)
        XCTAssertEqual(prefs.animationDuration, 0.16)
    }

    func testLoadReadsOverriddenValues() {
        let store = freshStore()
        store.set(0.5, forKey: Preferences.Key.widthFraction)
        store.set("left", forKey: Preferences.Key.horizontalAlignment)
        store.set("main", forKey: Preferences.Key.screenChoice)
        store.set("Menlo", forKey: Preferences.Key.fontName)
        store.set(14, forKey: Preferences.Key.fontSize)

        let prefs = Preferences.load(from: store)
        XCTAssertEqual(prefs.widthFraction, 0.5)
        XCTAssertEqual(prefs.horizontalAlignment, .left)
        XCTAssertEqual(prefs.screenChoice, .main)
        XCTAssertEqual(prefs.fontName, "Menlo")
        XCTAssertEqual(prefs.fontSize, 14)
    }

    func testFractionsAreClampedToValidRange() {
        let store = freshStore()
        store.set(5.0, forKey: Preferences.Key.widthFraction)      // > 1.0
        store.set(-0.5, forKey: Preferences.Key.heightFraction)    // < 0.1
        let prefs = Preferences.load(from: store)
        XCTAssertEqual(prefs.widthFraction, 1.0)
        XCTAssertEqual(prefs.heightFraction, 0.1)
    }

    func testOpacityIsClampedToValidRange() {
        let store = freshStore()
        store.set(2.5, forKey: Preferences.Key.backgroundOpacity)
        store.set(0.1, forKey: Preferences.Key.backgroundOpacity)  // < 0.3
        var prefs = Preferences.load(from: store)
        XCTAssertEqual(prefs.backgroundOpacity, 0.3)

        store.set(2.5, forKey: Preferences.Key.backgroundOpacity)
        prefs = Preferences.load(from: store)
        XCTAssertEqual(prefs.backgroundOpacity, 1.0)
    }

    func testUnknownEnumValueFallsBackToDefault() {
        let store = freshStore()
        store.set("upside-down", forKey: Preferences.Key.horizontalAlignment)
        let prefs = Preferences.load(from: store)
        XCTAssertEqual(prefs.horizontalAlignment, Preferences.defaults.horizontalAlignment)
    }

    func testDropdownFrameCenteredOnScreen() {
        var prefs = Preferences.defaults
        prefs.widthFraction = 0.5
        prefs.heightFraction = 0.4
        prefs.horizontalAlignment = .center

        let screen = NSRect(x: 0, y: 0, width: 2000, height: 1000)
        let visible = screen   // pretend visibleFrame == frame for test
        let mock = MockScreen(visible: visible)
        let frame = prefs.dropdownFrame(on: mock)

        XCTAssertEqual(frame.width, 1000)
        XCTAssertEqual(frame.height, 400)
        XCTAssertEqual(frame.minX, 500)      // centered: (2000 - 1000) / 2
        XCTAssertEqual(frame.maxY, 1000)     // anchored to top of visibleFrame
    }

    func testDropdownFrameRightAligned() {
        var prefs = Preferences.defaults
        prefs.widthFraction = 0.3
        prefs.horizontalAlignment = .right
        let mock = MockScreen(visible: NSRect(x: 100, y: 0, width: 1000, height: 800))
        let frame = prefs.dropdownFrame(on: mock)
        XCTAssertEqual(frame.width, 300)
        XCTAssertEqual(frame.maxX, 1100)
    }

    func testTerminalFontFallsBackToSystemMonospaced() {
        var prefs = Preferences.defaults
        prefs.fontName = "ThisFontDoesNotExistAnywhere"
        prefs.fontSize = 15
        let font = prefs.terminalFont()
        // No specific name guaranteed, but it should be a real monospaced font of the right size.
        XCTAssertEqual(font.pointSize, 15)
    }

    func testTerminalFontHonorsKnownFamily() {
        var prefs = Preferences.defaults
        prefs.fontName = "Menlo"
        prefs.fontSize = 12
        let font = prefs.terminalFont()
        XCTAssertEqual(font.familyName, "Menlo")
        XCTAssertEqual(font.pointSize, 12)
    }
}

/// Lets us hand a known visibleFrame to dropdownFrame(on:) without instantiating NSScreen.
private final class MockScreen: NSScreen {
    private let _visible: NSRect
    init(visible: NSRect) {
        self._visible = visible
        super.init()
    }
    required init?(coder: NSCoder) { fatalError() }
    override var visibleFrame: NSRect { _visible }
}
