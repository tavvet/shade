import Combine
import Foundation
import ShadeCore

/// Shared application state for the saved-connection library.
///
/// Settings edits, the quick picker and keyboard slots all observe this single
/// object, while file persistence and terminal creation stay behind injected
/// boundaries. Mutations are published only after a successful atomic save.
@MainActor
final class SSHConnectionsController: ObservableObject {
    @Published private(set) var profiles: [SSHProfile] = []
    @Published private(set) var problem: SSHConnectionsProblem?
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false

    private let store: any SSHProfileStoring
    private let connectAction: @MainActor (SSHProfile) throws -> Void
    private var libraryIsLoaded = false
    private var libraryRevision = 0
    private var completedReloadRevision: Int?
    private var reloadTask: Task<Void, Never>?
    private var saveTask: Task<Void, Error>?

    var canEditProfiles: Bool { libraryIsLoaded && !isLoading && !isSaving }
    var canConnectProfiles: Bool { !isLoading && completedReloadRevision == libraryRevision }

    init(
        store: any SSHProfileStoring = SSHProfileStore(),
        connect: @escaping @MainActor (SSHProfile) throws -> Void
    ) {
        self.store = store
        connectAction = connect
    }

    /// Re-attempts a failed load without discarding the last in-memory snapshot.
    /// Until this succeeds, writes remain blocked so corrupt/newer on-disk data
    /// can never be silently replaced with an empty library.
    func reload() async {
        repeat {
            if let reloadTask {
                await reloadTask.value
            } else {
                isLoading = true
                let pendingSave = saveTask
                let task = Task { await reloadLibrary(after: pendingSave) }
                reloadTask = task
                await task.value
            }
            // A location change can arrive after the task finishes but before
            // its callers resume. They must wait for the new backend as well.
        } while isLoading || completedReloadRevision != libraryRevision
    }

    /// Called synchronously when the selected configuration changes. Keep the
    /// cached display, but do not authorize edits or publish an old load result.
    func invalidateLibrary() {
        libraryRevision &+= 1
        libraryIsLoaded = false
        isLoading = true
    }

    private func reloadLibrary(after pendingSave: Task<Void, Error>?) async {
        // Clear the shared handle before the task completes, not in a caller's
        // later continuation that could otherwise coalesce a fresh reload away.
        defer { reloadTask = nil; isLoading = false }
        _ = await pendingSave?.result
        while true {
            let revision = libraryRevision
            do {
                let loaded = try SSHProfileStore.validated(await store.load())
                guard revision == libraryRevision else { continue }
                profiles = loaded
                libraryIsLoaded = true
                if problem?.kind == .load { problem = nil }
            } catch {
                guard revision == libraryRevision else { continue }
                libraryIsLoaded = false
                problem = SSHConnectionsProblem(kind: .load, message: error.localizedDescription)
            }
            completedReloadRevision = revision
            return
        }
    }

    @discardableResult
    func add(_ profile: SSHProfile) async throws -> SSHProfile {
        let profile = try profile.normalized()
        try await persist(profiles + [profile])
        return profile
    }

    func update(_ profile: SSHProfile, replacing original: SSHProfile? = nil) async throws {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else {
            throw SSHConnectionsControllerError.profileNotFound(profile.id)
        }
        var updated = profiles
        if let original, updated[index] != original {
            throw SSHConnectionsControllerError.profileChanged
        }
        updated[index] = try profile.normalized()
        try await persist(updated)
    }

    func remove(id: UUID, replacing original: SSHProfile? = nil) async throws {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else {
            throw SSHConnectionsControllerError.profileNotFound(id)
        }
        var updated = profiles
        if let original, updated[index] != original {
            throw SSHConnectionsControllerError.profileChanged
        }
        updated.remove(at: index)
        try await persist(updated)
    }

    /// Moves one profile to its final zero-based position. Array order is also
    /// the stable order used by ⌘⇧1…9 quick slots.
    func move(id: UUID, to destinationIndex: Int) async throws {
        guard let sourceIndex = profiles.firstIndex(where: { $0.id == id }) else {
            throw SSHConnectionsControllerError.profileNotFound(id)
        }
        let destinationIndex = min(max(0, destinationIndex), profiles.count - 1)
        guard sourceIndex != destinationIndex else { return }

        var updated = profiles
        let profile = updated.remove(at: sourceIndex)
        updated.insert(profile, at: destinationIndex)
        try await persist(updated)
    }

    /// Connects through the app-provided terminal action. A failed connection
    /// is reported without coupling shared connection state to picker lifetime.
    @discardableResult
    func connect(to id: UUID) -> Bool {
        guard canConnectProfiles else { return false }
        guard let profile = profiles.first(where: { $0.id == id }) else {
            reportActionProblem(SSHConnectionsProblem(
                kind: .connection,
                message: SSHConnectionsControllerError.profileNotFound(id).localizedDescription
            ))
            return false
        }

        do {
            try connectAction(profile)
            if problem?.kind == .connection { problem = nil }
            return true
        } catch {
            reportActionProblem(
                SSHConnectionsProblem(kind: .connection, message: error.localizedDescription)
            )
            return false
        }
    }

    /// One-based slot number matching the user-visible keyboard shortcut.
    @discardableResult
    func connectQuickSlot(_ number: Int) -> Bool {
        guard number > 0, profiles.indices.contains(number - 1) else { return false }
        return connect(to: profiles[number - 1].id)
    }

    func dismissProblem() {
        guard problem?.kind != .load else { return }
        problem = nil
    }

    func waitForPendingSave() async { _ = await saveTask?.result }

    private func persist(_ candidate: [SSHProfile]) async throws {
        guard libraryIsLoaded else {
            throw SSHConnectionsControllerError.libraryUnavailable
        }
        guard !isLoading, !isSaving else { throw SSHConnectionsControllerError.operationInProgress }
        let candidate = try SSHProfileStore.validated(candidate)
        let previous = profiles
        let revision = libraryRevision
        isSaving = true
        let task = Task { @MainActor in
            try await store.save(candidate, replacing: previous)
            guard revision == libraryRevision else { return }
            profiles = candidate
            if problem?.kind == .save { problem = nil }
        }
        saveTask = task
        defer { saveTask = nil; isSaving = false }
        do {
            try await task.value
        } catch {
            reportActionProblem(
                SSHConnectionsProblem(kind: .save, message: error.localizedDescription)
            )
            throw error
        }
    }

    /// A corrupt or unsupported library is the highest-priority problem because
    /// hiding it could make the blocked-write state look like an empty library.
    private func reportActionProblem(_ actionProblem: SSHConnectionsProblem) {
        guard problem?.kind != .load else { return }
        problem = actionProblem
    }
}

struct SSHConnectionsProblem: Equatable, Identifiable {
    enum Kind: String, Equatable {
        case load
        case save
        case connection
    }

    let kind: Kind
    let message: String

    var id: String { kind.rawValue + ":" + message }
}

enum SSHConnectionsControllerError: Error, Equatable, LocalizedError {
    case libraryUnavailable
    case profileNotFound(UUID)
    case profileChanged
    case operationInProgress

    var errorDescription: String? {
        switch self {
        case .libraryUnavailable:
            return "Connections cannot be changed until the library loads successfully."
        case .profileNotFound:
            return "The selected connection no longer exists."
        case .profileChanged:
            return "This connection changed while the editor or confirmation was open. Cancel and reopen it to use the latest values."
        case .operationInProgress:
            return "Wait for the current connection operation to finish, then try again."
        }
    }
}
