import XCTest
@testable import Shade
@testable import ShadeCore

final class CommandNotificationCoordinatorTests: XCTestCase {
    func testPanelShowRequestsAuthorizationOnlyWhenNotificationsAreEnabled() async {
        await MainActor.run {
            let requester = NotificationAuthorizationRequesterSpy()
            let coordinator = CommandNotificationCoordinator(
                terminals: TerminalsController(preferences: StaticPreferences()),
                panel: DropdownPanel(preferences: StaticPreferences()),
                preferences: StaticPreferences(),
                authorizationRequester: requester
            )
            var preferences = Preferences.defaults

            coordinator.panelWillShow(preferences: preferences)
            XCTAssertEqual(requester.requestIfNeededCount, 0)

            preferences.notifyOnCommandFinish = true
            coordinator.panelWillShow(preferences: preferences)
            XCTAssertEqual(requester.requestIfNeededCount, 1)
        }
    }
}

@MainActor
private final class NotificationAuthorizationRequesterSpy: NotificationAuthorizationRequesting {
    private(set) var requestIfNeededCount = 0

    func requestAuthorizationIfNeeded() {
        requestIfNeededCount += 1
    }
}
