import AppKit
import SwiftUI
import XCTest
@testable import Shade
@testable import ShadeCore

/// Exercises the dependency wiring AppDelegate builds, without launching the
/// app (no global hotkey, menus or system notifications).
@MainActor
final class AppDelegateWiringTests: XCTestCase {
    func testSavedPreferencesReachOpenTabsAndTheTabBar() async throws {
        let fixture = try ConfigurationFixture()
        defer { fixture.cleanup() }
        let configuration = fixture.store()
        let delegate = AppDelegate(configuration: configuration)
        delegate.connectComponents()
        let session = delegate.terminals.newSession(configuration: .waitingForTermination)
        defer { stop(session) }
        XCTAssertEqual(session.view.font.pointSize, 17)

        var updated = configuration.load()
        updated.fontSize = 20
        updated.tabMinimumWidth = 200
        try await configuration.save(updated, replacing: configuration.load())
        await configuration.waitForPendingAnnouncement()

        XCTAssertEqual(session.view.font.pointSize, 20)
        XCTAssertEqual(tabBarHost(in: delegate.panel)?.rootView.minimumTabWidth, 200)
    }

    func testAnnouncementsFromAnotherStoreAreIgnored() async throws {
        let fixture = try ConfigurationFixture()
        let other = try ConfigurationFixture()
        defer {
            fixture.cleanup()
            other.cleanup()
        }
        let delegate = AppDelegate(configuration: fixture.store())
        delegate.connectComponents()
        let session = delegate.terminals.newSession(configuration: .waitingForTermination)
        defer { stop(session) }

        let otherConfiguration = other.store()
        // Visible through the delegate's own store only after its next reload.
        fixture.defaults.set(25, forKey: PreferencesStore.Key.fontSize)
        try await otherConfiguration.updateFontSize { _ in 30 }
        await otherConfiguration.waitForPendingAnnouncement()

        XCTAssertEqual(session.view.font.pointSize, 17)
    }

    func testNewTabsUseTheDelegateStore() throws {
        let fixture = try ConfigurationFixture()
        defer { fixture.cleanup() }
        fixture.defaults.set("bar", forKey: PreferencesStore.Key.cursorShape)
        let delegate = AppDelegate(configuration: fixture.store())

        let session = delegate.terminals.newSession(configuration: .waitingForTermination)
        defer { stop(session) }

        XCTAssertEqual(session.view.font.pointSize, 17)
        XCTAssertEqual(session.view.terminalStateSnapshot().cursorStyle, .steadyBar)
    }

    func testConnectingComponentsTwiceKeepsOneSetOfSubscriptions() throws {
        let fixture = try ConfigurationFixture()
        defer { fixture.cleanup() }
        let delegate = AppDelegate(configuration: fixture.store())

        delegate.connectComponents()
        let content = try XCTUnwrap(delegate.panel.contentView)
        delegate.connectComponents()

        XCTAssertTrue(delegate.panel.contentView === content)
    }

    func testMenuCutReachesTheKeyboardControllerAndItsPasteboard() throws {
        let fixture = try ConfigurationFixture()
        defer { fixture.cleanup() }
        let pasteboard = privatePasteboard()
        defer { pasteboard.releaseGlobally() }
        let delegate = AppDelegate(configuration: fixture.store(), pasteboard: pasteboard)
        let session = delegate.terminals.newSession(configuration: .waitingForTermination)
        defer { stop(session) }
        session.view.feed(text: "echo hello")
        session.view.extendShadeKeyboardSelection(direction: .left, byWord: true)

        delegate.applicationMenuCutSelection()

        XCTAssertEqual(pasteboard.string(forType: .string), "hello")
        XCTAssertNil(session.view.getSelection())
    }

    func testCopyOutputShortcutUsesTheDelegatePasteboard() throws {
        let fixture = try ConfigurationFixture()
        defer { fixture.cleanup() }
        let pasteboard = privatePasteboard()
        defer { pasteboard.releaseGlobally() }
        let delegate = AppDelegate(configuration: fixture.store(), pasteboard: pasteboard)
        let session = delegate.terminals.newSession(configuration: .waitingForTermination)
        defer { stop(session) }
        let view = try XCTUnwrap(session.view as? ActivityTerminalView)
        let stream = Array("\u{1B}]133;C\u{07}copied output\r\n\u{1B}]133;D;0\u{07}".utf8)
        view.dataReceived(slice: stream[...])
        waitForCondition { session.promptMarks.count == 2 }
        let oKey = try XCTUnwrap(KeyCodes.asciiLetterForKeyCode.first { $0.value == "o" }?.key)
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command, .shift], timestamp: 0,
            windowNumber: 0, context: nil, characters: "O", charactersIgnoringModifiers: "O",
            isARepeat: false, keyCode: oKey
        ))

        XCTAssertEqual(delegate.panel.keyHandler?.panelHandleKey(event), true)

        XCTAssertEqual(pasteboard.string(forType: .string), "copied output")
    }

    private func privatePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("shade-tests-\(UUID().uuidString)"))
    }

    private func stop(_ session: TerminalSession) {
        session.onExit = nil
        session.terminate()
    }

    private func tabBarHost(in panel: NSPanel) -> NSHostingView<TabBarView>? {
        guard let root = panel.contentView else { return nil }
        return descendants(of: root).compactMap { $0 as? NSHostingView<TabBarView> }.first
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(descendants(of:))
    }
}
