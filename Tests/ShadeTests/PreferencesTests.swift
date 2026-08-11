import XCTest
import AppKit
@testable import Shade

final class PreferencesTests: XCTestCase {
    private func freshStore() -> UserDefaults {
        let suite = "ShadeTests-" + UUID().uuidString
        return UserDefaults(suiteName: suite)!
    }

    func testLoadReturnsDefaultsWhenStoreIsEmpty() {
        let prefs = PreferencesStore(userDefaults: freshStore()).load()
        XCTAssertEqual(prefs.widthFraction, Preferences.defaults.widthFraction)
        XCTAssertEqual(prefs.heightFraction, Preferences.defaults.heightFraction)
        XCTAssertEqual(prefs.horizontalAlignment, .center)
        XCTAssertEqual(prefs.screenChoice, .mouseLocation)
        XCTAssertEqual(prefs.fontName, "")
        XCTAssertEqual(prefs.backgroundOpacity, 0.94)
        XCTAssertEqual(prefs.animationDuration, 0.16)
        XCTAssertTrue(prefs.backgroundBlur)
        XCTAssertFalse(prefs.hideOnFocusLoss)
        XCTAssertEqual(prefs.blurMaterial, .hud)
        XCTAssertFalse(prefs.newTabInheritsCwd)
        XCTAssertEqual(prefs.cursorShape, .block)
        XCTAssertFalse(prefs.cursorBlink)
        XCTAssertFalse(prefs.visualBell)
    }

    func testLoadReadsOverriddenValues() {
        let store = freshStore()
        store.set(0.5, forKey: PreferencesStore.Key.widthFraction)
        store.set("left", forKey: PreferencesStore.Key.horizontalAlignment)
        store.set("main", forKey: PreferencesStore.Key.screenChoice)
        store.set("Menlo", forKey: PreferencesStore.Key.fontName)
        store.set(14, forKey: PreferencesStore.Key.fontSize)

        let prefs = PreferencesStore(userDefaults: store).load()
        XCTAssertEqual(prefs.widthFraction, 0.5)
        XCTAssertEqual(prefs.horizontalAlignment, .left)
        XCTAssertEqual(prefs.screenChoice, .main)
        XCTAssertEqual(prefs.fontName, "Menlo")
        XCTAssertEqual(prefs.fontSize, 14)
    }

    func testSaveRoundTripsEveryPreference() {
        let store = freshStore()
        var prefs = Preferences.defaults
        prefs.widthFraction = 0.35
        prefs.heightFraction = 0.65
        prefs.horizontalAlignment = .right
        prefs.screenChoice = .main
        prefs.fontSize = 17
        prefs.fontName = "Menlo"
        prefs.backgroundOpacity = 0.75
        prefs.animationDuration = 0.3
        prefs.linkHighlightHex = "123ABC"
        prefs.backgroundBlur = false
        prefs.notifyOnCommandFinish = true
        prefs.notifyThresholdSeconds = 90
        prefs.hideOnFocusLoss = true
        prefs.blurMaterial = .sidebar
        prefs.newTabInheritsCwd = true
        prefs.shellEnrichment = true
        prefs.cursorShape = .underline
        prefs.cursorBlink = true
        prefs.visualBell = true

        PreferencesStore(userDefaults: store).save(prefs)

        XCTAssertEqual(PreferencesStore(userDefaults: store).load(), prefs)
    }

    func testSavingFontSizeDoesNotRewriteUnrelatedRawValues() {
        let userDefaults = freshStore()
        let store = PreferencesStore(userDefaults: userDefaults)
        userDefaults.set("future-material", forKey: PreferencesStore.Key.blurMaterial)

        store.saveFontSize(18)

        XCTAssertEqual(userDefaults.double(forKey: PreferencesStore.Key.fontSize), 18)
        XCTAssertEqual(
            userDefaults.string(forKey: PreferencesStore.Key.blurMaterial),
            "future-material"
        )
    }

    func testBackgroundBlurReadsStoredValue() {
        let store = freshStore()
        store.set(false, forKey: PreferencesStore.Key.backgroundBlur)
        XCTAssertFalse(PreferencesStore(userDefaults: store).load().backgroundBlur)

        store.set(true, forKey: PreferencesStore.Key.backgroundBlur)
        XCTAssertTrue(PreferencesStore(userDefaults: store).load().backgroundBlur)
    }

    func testHideOnFocusLossReadsStoredValue() {
        let store = freshStore()
        store.set(true, forKey: PreferencesStore.Key.hideOnFocusLoss)
        XCTAssertTrue(PreferencesStore(userDefaults: store).load().hideOnFocusLoss)
    }

    func testBlurMaterialReadsStoredValueAndFallsBack() {
        let store = freshStore()
        store.set("sidebar", forKey: PreferencesStore.Key.blurMaterial)
        XCTAssertEqual(PreferencesStore(userDefaults: store).load().blurMaterial, .sidebar)
        store.set("bogus", forKey: PreferencesStore.Key.blurMaterial)
        XCTAssertEqual(PreferencesStore(userDefaults: store).load().blurMaterial, Preferences.defaults.blurMaterial)
    }

    func testNewTabInheritsCwdReadsStoredValue() {
        let store = freshStore()
        store.set(true, forKey: PreferencesStore.Key.newTabInheritsCwd)
        XCTAssertTrue(PreferencesStore(userDefaults: store).load().newTabInheritsCwd)
    }

    func testCursorShapeReadsStoredValue() {
        let store = freshStore()
        store.set("bar", forKey: PreferencesStore.Key.cursorShape)
        XCTAssertEqual(PreferencesStore(userDefaults: store).load().cursorShape, .bar)
    }

    func testLoadNormalizesValidLinkHighlightHex() {
        let store = freshStore()
        store.set("#ffcc00", forKey: PreferencesStore.Key.linkHighlightHex)

        XCTAssertEqual(PreferencesStore(userDefaults: store).load().linkHighlightHex, "FFCC00")
    }

    func testCursorDECSCUSR() {
        var p = Preferences.defaults
        p.cursorShape = .block; p.cursorBlink = false
        XCTAssertEqual(p.cursorDECSCUSR, "\u{1B}[2 q")
        p.cursorBlink = true
        XCTAssertEqual(p.cursorDECSCUSR, "\u{1B}[1 q")
        p.cursorShape = .bar; p.cursorBlink = false
        XCTAssertEqual(p.cursorDECSCUSR, "\u{1B}[6 q")
        p.cursorShape = .underline; p.cursorBlink = true
        XCTAssertEqual(p.cursorDECSCUSR, "\u{1B}[3 q")
    }

    func testFractionsAreClampedToValidRange() {
        let store = freshStore()
        store.set(5.0, forKey: PreferencesStore.Key.widthFraction)      // > 1.0
        store.set(-0.5, forKey: PreferencesStore.Key.heightFraction)    // < 0.1
        let prefs = PreferencesStore(userDefaults: store).load()
        XCTAssertEqual(prefs.widthFraction, 1.0)
        XCTAssertEqual(prefs.heightFraction, 0.1)
    }

    func testOpacityIsClampedToValidRange() {
        let store = freshStore()
        store.set(2.5, forKey: PreferencesStore.Key.backgroundOpacity)
        store.set(0.1, forKey: PreferencesStore.Key.backgroundOpacity)  // < 0.3
        var prefs = PreferencesStore(userDefaults: store).load()
        XCTAssertEqual(prefs.backgroundOpacity, 0.3)

        store.set(2.5, forKey: PreferencesStore.Key.backgroundOpacity)
        prefs = PreferencesStore(userDefaults: store).load()
        XCTAssertEqual(prefs.backgroundOpacity, 1.0)
    }

    func testUnknownEnumValueFallsBackToDefault() {
        let store = freshStore()
        store.set("upside-down", forKey: PreferencesStore.Key.horizontalAlignment)
        let prefs = PreferencesStore(userDefaults: store).load()
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

    func testParseHexAcceptsSixCharStringWithOrWithoutHash() {
        let a = Preferences.parseHex("FFCC00")
        let b = Preferences.parseHex("#ffcc00")
        XCTAssertNotNil(a)
        XCTAssertNotNil(b)
        let target = NSColor(red: 1, green: 0.8, blue: 0, alpha: 1)
        for color in [a!, b!] {
            let srgb = color.usingColorSpace(.sRGB)!
            XCTAssertEqual(Double(srgb.redComponent),   1.0, accuracy: 0.01)
            XCTAssertEqual(Double(srgb.greenComponent), 0.8, accuracy: 0.01)
            XCTAssertEqual(Double(srgb.blueComponent),  0.0, accuracy: 0.01)
            _ = target  // silence unused
        }
    }

    func testParseHexRejectsBadInput() {
        XCTAssertNil(Preferences.parseHex(""))
        XCTAssertNil(Preferences.parseHex("12345"))    // too short
        XCTAssertNil(Preferences.parseHex("ZZZZZZ"))   // not hex
        XCTAssertNil(Preferences.parseHex("FFCC0000")) // too long (no alpha support)
    }

    func testLinkHighlightColorFallsBackForGarbageInput() {
        var prefs = Preferences.defaults
        prefs.linkHighlightHex = "not-a-color"
        XCTAssertEqual(prefs.linkHighlightColor(), NSColor.systemYellow)
    }

    func testSetLinkHighlightColorStoresRGBHex() {
        var prefs = Preferences.defaults

        prefs.setLinkHighlightColor(NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 0.5))

        XCTAssertEqual(prefs.linkHighlightHex, "336699")
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
