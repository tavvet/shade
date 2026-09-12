import Foundation

/// Resolves a picker action against the latest library, without tying its
/// asynchronous lifetime to an AppKit window. Dismissal cancels the action,
/// while the controller's shared reload may still finish for other consumers.
@MainActor
final class SSHConnectionPickerConnectionRequest {
    enum Target {
        case profile(UUID)
        case quickSlot(Int)
    }

    private let controller: SSHConnectionsController
    private var pendingTask: Task<Void, Never>?

    init(controller: SSHConnectionsController) {
        self.controller = controller
    }

    @discardableResult
    func connect(
        _ target: Target,
        onConnected: @escaping @MainActor () -> Void
    ) -> Task<Void, Never> {
        cancel()
        let controller = controller
        let task = Task { @MainActor in
            guard !Task.isCancelled else { return }
            await controller.reload()
            guard !Task.isCancelled else { return }

            // A failed refresh intentionally leaves the controller's cached
            // library usable. Never use it before that refresh has finished.
            let connected: Bool
            switch target {
            case .profile(let id):
                connected = controller.connect(to: id)
            case .quickSlot(let number):
                connected = controller.connectQuickSlot(number)
            }
            if connected { onConnected() }
        }
        pendingTask = task
        return task
    }

    func cancel() {
        pendingTask?.cancel()
        pendingTask = nil
    }
}
