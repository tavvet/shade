import AppKit
import XCTest
@testable import Shade

final class PanelShortcutResolverTests: XCTestCase {
    func testZoomShortcutsUsePhysicalKeys() {
        XCTAssertEqual(resolve(KeyCodes.equal, flags: [.command]), .zoomIn)
        XCTAssertEqual(resolve(KeyCodes.equal, flags: [.command, .shift]), .zoomIn)
        XCTAssertEqual(resolve(KeyCodes.minus, flags: [.command]), .zoomOut)
        XCTAssertEqual(resolve(KeyCodes.zero, flags: [.command]), .resetZoom)
    }

    func testLetterShortcutsIgnoreCurrentInputSourceCharacters() {
        XCTAssertEqual(resolve(key("t"), characters: "е", flags: [.command]), .newTab)
        XCTAssertEqual(resolve(key("w"), characters: "ц", flags: [.command]), .closeTab)
        XCTAssertEqual(resolve(key("k"), characters: "л", flags: [.command]), .clearScreen)
    }

    func testNumberShortcutOnlyConsumesExistingTab() {
        XCTAssertEqual(resolve(key("q"), characters: "3", flags: [.command], tabCount: 3), .selectTab(2))
        XCTAssertNil(resolve(key("q"), characters: "4", flags: [.command], tabCount: 3))
    }

    func testControlTabNavigation() {
        XCTAssertEqual(resolve(KeyCodes.tab, flags: [.control]), .nextTab)
        XCTAssertEqual(resolve(KeyCodes.tab, flags: [.control, .shift]), .previousTab)
    }

    func testPromptShortcutsMaskSystemArrowFlags() {
        XCTAssertEqual(
            resolve(KeyCodes.upArrow, flags: [.command, .shift, .function, .numericPad]),
            .previousPrompt
        )
        XCTAssertEqual(
            resolve(KeyCodes.downArrow, flags: [.command, .shift, .function, .numericPad]),
            .nextPrompt
        )
        XCTAssertEqual(resolve(key("o"), characters: "щ", flags: [.command, .shift]), .copyLastCommandOutput)
    }

    func testUnmatchedShortcutFallsThrough() {
        XCTAssertNil(resolve(key("t"), characters: "t", flags: []))
        XCTAssertNil(resolve(KeyCodes.upArrow, flags: [.command]))
    }

    private func resolve(
        _ keyCode: UInt16,
        characters: String = "",
        flags: NSEvent.ModifierFlags,
        tabCount: Int = 3
    ) -> PanelShortcut? {
        PanelShortcutResolver.resolve(
            keyCode: keyCode,
            charactersIgnoringModifiers: characters,
            modifierFlags: flags,
            tabCount: tabCount
        )
    }

    private func key(_ letter: Character) -> UInt16 {
        KeyCodes.asciiLetterForKeyCode.first(where: { $0.value == letter })!.key
    }
}
