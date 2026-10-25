import AppKit
import SwiftUI
import XCTest
@testable import Shade
@testable import ShadeCore

@MainActor
final class TerminalPanelContentControllerTests: XCTestCase {
    func testInstallBuildsTerminalTabBarAndBlurFromPreferences() throws {
        var prefs = Preferences.defaults
        prefs.backgroundBlur = false
        prefs.blurMaterial = .sidebar
        prefs.tabMinimumWidth = 150
        prefs.showInputSourceIndicator = true
        let fixture = Fixture()

        fixture.content.install(in: fixture.panel, preferences: prefs)

        let root = try XCTUnwrap(fixture.panel.contentView)
        let blur = try XCTUnwrap(descendants(of: root).compactMap { $0 as? NSVisualEffectView }.first)
        XCTAssertTrue(blur.isHidden)
        XCTAssertEqual(blur.material, .sidebar)
        XCTAssertEqual(blur.blendingMode, .behindWindow)

        let tabBar = try XCTUnwrap(tabBarHost(in: root))
        XCTAssertEqual(tabBar.rootView.minimumTabWidth, 150)
        XCTAssertTrue(tabBar.constraints.contains {
            $0.firstAttribute == .height && $0.constant == TabBarLayout.height
        })
        XCTAssertTrue(fixture.terminals.containerView.isDescendant(of: root))
        XCTAssertTrue(fixture.inputSource.isEnabled)
    }

    func testApplyUpdatesBlurTabWidthAndInputSource() throws {
        var prefs = Preferences.defaults
        prefs.backgroundBlur = true
        prefs.blurMaterial = .hud
        prefs.showInputSourceIndicator = false
        let fixture = Fixture()
        fixture.content.install(in: fixture.panel, preferences: prefs)

        prefs.backgroundBlur = false
        prefs.blurMaterial = .fullScreen
        prefs.tabMinimumWidth = 220
        prefs.showInputSourceIndicator = true
        fixture.content.apply(prefs)

        let root = try XCTUnwrap(fixture.panel.contentView)
        let blur = try XCTUnwrap(descendants(of: root).compactMap { $0 as? NSVisualEffectView }.first)
        XCTAssertTrue(blur.isHidden)
        XCTAssertEqual(blur.material, .fullScreenUI)
        XCTAssertEqual(try XCTUnwrap(tabBarHost(in: root)).rootView.minimumTabWidth, 220)
        XCTAssertTrue(fixture.inputSource.isEnabled)
    }

    private func tabBarHost(in root: NSView) -> NSHostingView<TabBarView>? {
        descendants(of: root).compactMap { $0 as? NSHostingView<TabBarView> }.first
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(descendants(of:))
    }
}

@MainActor
private struct Fixture {
    let terminals = TerminalsController(preferences: StaticPreferences())
    let panel = DropdownPanel(preferences: StaticPreferences())
    let inputSource = InputSourceMonitor(
        provider: NoInputSource(),
        notificationCenter: NotificationCenter()
    )
    let content: TerminalPanelContentController

    init() {
        content = TerminalPanelContentController(
            terminals: terminals,
            tabs: TabsObservable(controller: terminals),
            inputSource: inputSource
        )
    }
}

private struct NoInputSource: InputSourceProviding {
    func currentInputSource() -> InputSourceDescriptor? { nil }
}
