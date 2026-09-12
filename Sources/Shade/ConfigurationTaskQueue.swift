import Foundation

/// Serializes complete storage transactions, including publication on the main
/// actor. Suspending for disk I/O must not let a later reload or folder switch
/// publish its result ahead of an earlier save.
@MainActor
final class ConfigurationTaskQueue {
    private var tail: Task<Void, Never>?

    func waitForAll() async { await tail?.value }

    func run<Value: Sendable>(
        _ operation: @escaping @MainActor () async throws -> Value
    ) async throws -> Value {
        try await enqueue(operation).value
    }

    func enqueue<Value: Sendable>(
        _ operation: @escaping @MainActor () async throws -> Value
    ) -> Task<Value, Error> {
        let previous = tail
        let task = Task {
            await previous?.value
            return try await operation()
        }
        tail = Task { _ = await task.result }
        return task
    }
}

enum ConfigurationDisk {
    /// NSFileCoordinator and file-provider metadata calls can wait even when a
    /// document is downloaded. None of them may execute on the main actor.
    static func run<Value: Sendable>(
        _ operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        try await Task.detached(priority: .userInitiated, operation: operation).value
    }
}
