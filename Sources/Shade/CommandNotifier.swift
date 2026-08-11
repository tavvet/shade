import AppKit
import UserNotifications

/// Posts a native notification when a command finishes while the panel is hidden.
/// Timing comes from OSC 133 C→D marks recorded per session, so this only fires
/// when the shell integration is installed; without it there are no marks.
@MainActor
final class CommandNotifier: NSObject {
    /// Invoked when the user clicks a delivered notification (e.g. to reveal the panel).
    var onActivate: (() -> Void)?

    /// Install as the notification-center delegate so banners show even while the
    /// app is technically active (the panel can be hidden yet the app frontmost).
    func start() {
        UNUserNotificationCenter.current().delegate = self
    }

    func post(exitCode: Int?, duration: TimeInterval, cwd: String) {
        let content = UNMutableNotificationContent()
        let ok = (exitCode ?? 0) == 0
        content.title = ok ? "Command finished" : "Command failed"
        var body = ok
            ? "Done in \(Self.humanDuration(duration))"
            : "Exit \(exitCode.map(String.init) ?? "?") · \(Self.humanDuration(duration))"
        let place = Self.abbreviateHome(cwd)
        if !place.isEmpty { body += " · \(place)" }
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// "45s" / "1m 5s" / "2h 3m". Seconds are dropped once we're past an hour.
    nonisolated static func humanDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total)s" }
        let m = total / 60, s = total % 60
        if m < 60 { return s == 0 ? "\(m)m" : "\(m)m \(s)s" }
        let h = m / 60, mm = m % 60
        return mm == 0 ? "\(h)h" : "\(h)h \(mm)m"
    }

    nonisolated static func abbreviateHome(_ path: String) -> String {
        guard !path.isEmpty else { return "" }
        let home = NSHomeDirectory()
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}

extension CommandNotifier: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
        Task { @MainActor in self.onActivate?() }
    }
}
