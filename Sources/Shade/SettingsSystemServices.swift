import ServiceManagement
import UserNotifications

@MainActor
protocol LoginItemManaging {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

@MainActor
struct SystemLoginItemManager: LoginItemManaging {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

@MainActor
protocol NotificationAuthorizationRequesting {
    func requestAuthorization()
}

@MainActor
struct SystemNotificationAuthorizationRequester: NotificationAuthorizationRequesting {
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}
