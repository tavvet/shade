import XCTest
@testable import Shade

@MainActor
final class SettingsModelTests: XCTestCase {
    func testReloadPreventsUnrelatedSaveFromOverwritingExternalFontZoom() async throws {
        let fixture = try ConfigurationFixture()
        defer { fixture.cleanup() }
        let configuration = fixture.store()
        let model = SettingsModel(preferences: configuration, openAtLogin: false)

        // An external `defaults write`, picked up by the store's next reload.
        fixture.defaults.set(14, forKey: PreferencesStore.Key.fontSize)
        _ = await configuration.reload()
        await configuration.waitForPendingAnnouncement()
        XCTAssertEqual(model.preferences.fontSize, 14)

        model.preferences.visualBell.toggle()
        await model.waitForPendingSave()
        XCTAssertEqual(fixture.defaults.double(forKey: PreferencesStore.Key.fontSize), 14)
    }

    func testModelIgnoresAnnouncementsFromOtherStores() async throws {
        let fixture = try ConfigurationFixture()
        let other = try ConfigurationFixture()
        defer {
            fixture.cleanup()
            other.cleanup()
        }
        let configuration = fixture.store()
        let otherConfiguration = other.store()
        let model = SettingsModel(preferences: configuration, openAtLogin: false)
        let shown = model.preferences

        // A change visible in this model's store, but announced by another one.
        fixture.defaults.set(19, forKey: PreferencesStore.Key.fontSize)
        try await otherConfiguration.updateFontSize { _ in 21 }
        await otherConfiguration.waitForPendingAnnouncement()

        XCTAssertEqual(model.preferences, shown)
    }

    func testNotificationAuthorizationIsRequestedOnlyWhenEnablingNotifications() async {
        let suite = "SettingsModelTests.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite)!
        defer { store.removePersistentDomain(forName: suite) }

        let requester = NotificationAuthorizationRequesterSpy()
        let model = SettingsModel(
            preferences: PreferencesStore(userDefaults: store),
            openAtLogin: false,
            notificationAuthorizationRequester: requester
        )

        model.preferences.notifyOnCommandFinish = true
        await model.waitForPendingSave()
        XCTAssertTrue(store.bool(forKey: PreferencesStore.Key.notifyOnCommandFinish))
        XCTAssertEqual(requester.requestCount, 1)

        model.preferences.notifyThresholdSeconds = 45
        await model.waitForPendingSave()
        model.preferences.notifyOnCommandFinish = true
        await model.waitForPendingSave()
        XCTAssertEqual(requester.requestCount, 1)

        model.preferences.notifyOnCommandFinish = false
        await model.waitForPendingSave()
        model.preferences.notifyOnCommandFinish = true
        await model.waitForPendingSave()
        XCTAssertEqual(requester.requestCount, 2)
    }

    func testExternalNotificationReloadDoesNotRequestAuthorization() async throws {
        let fixture = try ConfigurationFixture()
        defer { fixture.cleanup() }
        let configuration = fixture.store()

        let requester = NotificationAuthorizationRequesterSpy()
        let model = SettingsModel(
            preferences: configuration,
            openAtLogin: false,
            notificationAuthorizationRequester: requester
        )

        fixture.defaults.set(true, forKey: PreferencesStore.Key.notifyOnCommandFinish)
        _ = await configuration.reload()
        await configuration.waitForPendingAnnouncement()

        XCTAssertTrue(model.preferences.notifyOnCommandFinish)
        XCTAssertEqual(requester.requestCount, 0)
    }

    func testFailedLoginItemChangeRestoresActualState() async {
        let manager = LoginItemManagerStub(isEnabled: false)
        manager.error = StubError.rejected
        let model = SettingsModel(
            preferences: isolatedPreferencesStore(),
            openAtLogin: false,
            loginItemManager: manager
        )

        model.openAtLogin = true

        XCTAssertFalse(model.openAtLogin)
        XCTAssertEqual(manager.requestedValues, [true])
    }

    func testPresentationReloadRefreshesExternalLoginItemStateWithoutWriting() async {
        let manager = LoginItemManagerStub(isEnabled: false)
        let model = SettingsModel(
            preferences: isolatedPreferencesStore(),
            openAtLogin: false,
            loginItemManager: manager
        )

        manager.isEnabled = true
        model.reloadForPresentation()

        XCTAssertTrue(model.openAtLogin)
        XCTAssertEqual(manager.requestedValues, [])
    }
}

private enum StubError: Error {
    case rejected
}

@MainActor
private final class LoginItemManagerStub: LoginItemManaging {
    var isEnabled: Bool
    var error: Error?
    private(set) var requestedValues: [Bool] = []

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    func setEnabled(_ enabled: Bool) throws {
        requestedValues.append(enabled)
        if let error { throw error }
        isEnabled = enabled
    }
}

@MainActor
private final class NotificationAuthorizationRequesterSpy: NotificationAuthorizationRequesting {
    private(set) var requestCount = 0

    func requestAuthorizationIfNeeded() {
        requestCount += 1
    }
}
