import AppKit
import XCTest
@testable import Shade

@MainActor
final class InputSourceMonitorTests: XCTestCase {
    func testBadgeUsesUppercasedBaseLanguageCode() {
        XCTAssertEqual(
            descriptor(language: "en-US", name: "U.S.").badgeLabel,
            "EN"
        )
        XCTAssertEqual(
            descriptor(language: "zh-Hans", name: "Pinyin – Simplified").badgeLabel,
            "ZH"
        )
        XCTAssertEqual(
            descriptor(language: "rus", name: "Russian").badgeLabel,
            "RUS"
        )
        XCTAssertEqual(
            descriptor(language: "pt_BR", name: "Brazilian").badgeLabel,
            "PT"
        )
    }

    func testBadgeFallsBackToLocalizedNameWhenLanguageIsUnavailable() {
        XCTAssertEqual(
            descriptor(language: "", name: "Unicode Hex Input").badgeLabel,
            "Unicode Hex Input"
        )
        XCTAssertEqual(
            descriptor(language: nil, name: "  ").badgeLabel,
            "?"
        )
    }

    func testEnablingRefreshesAndNotificationTracksSourceChanges() {
        let center = NotificationCenter()
        let provider = InputSourceProviderStub(
            current: descriptor(language: "en", name: "ABC")
        )
        let monitor = InputSourceMonitor(provider: provider, notificationCenter: center)

        XCTAssertFalse(monitor.isEnabled)
        XCTAssertNil(monitor.current)
        XCTAssertEqual(provider.readCount, 0)

        monitor.setEnabled(true)

        XCTAssertTrue(monitor.isEnabled)
        XCTAssertEqual(monitor.current?.badgeLabel, "EN")
        XCTAssertEqual(provider.readCount, 1)

        provider.current = descriptor(language: "ru", name: "Russian")
        center.post(name: NSTextInputContext.keyboardSelectionDidChangeNotification, object: nil)

        XCTAssertEqual(monitor.current?.badgeLabel, "RU")
        XCTAssertEqual(provider.readCount, 2)
    }

    func testReapplyingEnabledRefreshesWithoutRegisteringDuplicateObserver() {
        let center = NotificationCenter()
        let provider = InputSourceProviderStub(
            current: descriptor(language: "en", name: "ABC")
        )
        let monitor = InputSourceMonitor(provider: provider, notificationCenter: center)

        monitor.setEnabled(true)
        monitor.setEnabled(true)
        XCTAssertEqual(provider.readCount, 2)

        center.post(name: NSTextInputContext.keyboardSelectionDidChangeNotification, object: nil)
        XCTAssertEqual(provider.readCount, 3)
    }

    func testDisablingClearsStateAndStopsObserving() {
        let center = NotificationCenter()
        let provider = InputSourceProviderStub(
            current: descriptor(language: "en", name: "ABC")
        )
        let monitor = InputSourceMonitor(provider: provider, notificationCenter: center)
        monitor.setEnabled(true)

        monitor.setEnabled(false)
        provider.current = descriptor(language: "ru", name: "Russian")
        center.post(name: NSTextInputContext.keyboardSelectionDidChangeNotification, object: nil)

        XCTAssertFalse(monitor.isEnabled)
        XCTAssertNil(monitor.current)
        XCTAssertEqual(provider.readCount, 1)
    }

    func testDiagnosticsDescribeDisabledUnavailableAndCurrentStates() {
        let provider = InputSourceProviderStub(current: nil)
        let monitor = InputSourceMonitor(
            provider: provider,
            notificationCenter: NotificationCenter()
        )

        XCTAssertEqual(monitor.diagnosticsDescription, "disabled")

        monitor.setEnabled(true)
        XCTAssertEqual(monitor.diagnosticsDescription, "unavailable")

        provider.current = descriptor(language: "fi", name: "Finnish")
        monitor.refresh()
        XCTAssertEqual(
            monitor.diagnosticsDescription,
            "FI — Finnish [test.fi]"
        )
    }

    private func descriptor(language: String?, name: String) -> InputSourceDescriptor {
        InputSourceDescriptor(
            identifier: "test.\(language ?? "none")",
            localizedName: name,
            primaryLanguage: language
        )
    }
}

private final class InputSourceProviderStub: InputSourceProviding {
    var current: InputSourceDescriptor?
    private(set) var readCount = 0

    init(current: InputSourceDescriptor?) {
        self.current = current
    }

    func currentInputSource() -> InputSourceDescriptor? {
        readCount += 1
        return current
    }
}
