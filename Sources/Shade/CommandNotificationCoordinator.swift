import Foundation

/// Bridges terminal command-completion events to user notifications.
@MainActor
final class CommandNotificationCoordinator {
    private let terminals: TerminalsController
    private let panel: DropdownPanel
    private let notifier: CommandNotifier

    init(
        terminals: TerminalsController,
        panel: DropdownPanel,
        notifier: CommandNotifier = CommandNotifier()
    ) {
        self.terminals = terminals
        self.panel = panel
        self.notifier = notifier
    }

    func start() {
        notifier.start()
        notifier.onActivate = { [weak self] in self?.panel.show() }
        terminals.commandFinishHandler = { [weak self] duration, exitCode, cwd in
            self?.handleCommandFinish(duration: duration, exitCode: exitCode, cwd: cwd)
        }
    }

    private func handleCommandFinish(duration: TimeInterval, exitCode: Int?, cwd: String) {
        guard !panel.isVisible else { return }
        let prefs = Preferences.load()
        guard prefs.notifyOnCommandFinish, duration >= prefs.notifyThresholdSeconds else { return }
        notifier.post(exitCode: exitCode, duration: duration, cwd: cwd)
    }
}
