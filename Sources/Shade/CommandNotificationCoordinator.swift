import Foundation

/// Bridges terminal command-completion events to user notifications.
@MainActor
final class CommandNotificationCoordinator {
    private let terminals: TerminalsController
    private let panel: DropdownPanel
    private let notifier: CommandNotifier
    private let authorizationRequester: any NotificationAuthorizationRequesting

    init(
        terminals: TerminalsController,
        panel: DropdownPanel,
        notifier: CommandNotifier = CommandNotifier(),
        authorizationRequester: any NotificationAuthorizationRequesting =
            SystemNotificationAuthorizationRequester()
    ) {
        self.terminals = terminals
        self.panel = panel
        self.notifier = notifier
        self.authorizationRequester = authorizationRequester
    }

    func start() {
        notifier.start()
        notifier.onActivate = { [weak self] in self?.panel.show() }
        terminals.commandFinishHandler = { [weak self] duration, exitCode, cwd in
            self?.handleCommandFinish(duration: duration, exitCode: exitCode, cwd: cwd)
        }
    }

    /// Handles notification preferences enabled outside the Settings UI. The
    /// panel show is an explicit user action, making it the appropriate moment
    /// to ask for system permission if macOS has not prompted yet.
    func panelWillShow(preferences: Preferences) {
        guard preferences.notifyOnCommandFinish else { return }
        authorizationRequester.requestAuthorizationIfNeeded()
    }

    private func handleCommandFinish(duration: TimeInterval, exitCode: Int?, cwd: String) {
        guard !panel.isVisible else { return }
        let prefs = Preferences.load()
        guard prefs.notifyOnCommandFinish, duration >= prefs.notifyThresholdSeconds else { return }
        notifier.post(exitCode: exitCode, duration: duration, cwd: cwd)
    }
}
