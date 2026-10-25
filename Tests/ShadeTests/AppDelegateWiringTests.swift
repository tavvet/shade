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
