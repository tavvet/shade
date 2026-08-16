import Combine
import Foundation

/// Shared application state for the saved-connection library.
///
/// Settings edits, the quick picker and keyboard slots all observe this single
/// object, while file persistence and terminal creation stay behind injected
/// boundaries. Mutations are published only after a successful atomic save.
@MainActor
final class SSHConnectionsController: ObservableObject {
    @Published private(set) var profiles: [SSHProfile] = []
    @Published private(set) var problem: SSHConnectionsProblem?
    @Published var isPickerPresented = false

    private let store: any SSHProfileStoring
    private let connectAction: @MainActor (SSHProfile) throws -> Void
    private var libraryIsLoaded = false

    init(
        store: any SSHProfileStoring = SSHProfileStore(),
        connect: @escaping @MainActor (SSHProfile) throws -> Void
    ) {
        self.store = store
        connectAction = connect
        reload()
    }

    /// Re-attempts a failed load without discarding the last in-memory snapshot.
    /// Until this succeeds, writes remain blocked so corrupt/newer on-disk data
    /// can never be silently replaced with an empty library.
    func reload() {
        do {
            let loaded = try SSHProfileStore.validated(store.load())
            profiles = loaded
            libraryIsLoaded = true
            if problem?.kind == .load { problem = nil }
        } catch {
            libraryIsLoaded = false
            problem = SSHConnectionsProblem(kind: .load, message: error.localizedDescription)
        }
    }

    @discardableResult
    func add(_ profile: SSHProfile) throws -> SSHProfile {
        let profile = try profile.normalized()
        try persist(profiles + [profile])
        return profile
    }

    func update(_ profile: SSHProfile) throws {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else {
            throw SSHConnectionsControllerError.profileNotFound(profile.id)
        }
        var updated = profiles
        updated[index] = try profile.normalized()
        try persist(updated)
    }

    func remove(id: UUID) throws {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else {
            throw SSHConnectionsControllerError.profileNotFound(id)
        }
        var updated = profiles
        updated.remove(at: index)
        try persist(updated)
    }

    /// Moves one profile to its final zero-based position. Array order is also
    /// the stable order used by ⌘⇧1…9 quick slots.
    func move(id: UUID, to destinationIndex: Int) throws {
        guard let sourceIndex = profiles.firstIndex(where: { $0.id == id }) else {
            throw SSHConnectionsControllerError.profileNotFound(id)
        }
        let destinationIndex = min(max(0, destinationIndex), profiles.count - 1)
        guard sourceIndex != destinationIndex else { return }

        var updated = profiles
        let profile = updated.remove(at: sourceIndex)
        updated.insert(profile, at: destinationIndex)
        try persist(updated)
    }

    func presentPicker() {
        isPickerPresented = true
    }

    func dismissPicker() {
        isPickerPresented = false
    }

    /// Connects through the app-provided terminal action. A failed connection
    /// keeps the picker open so the user can edit or retry the profile.
    @discardableResult
    func connect(to id: UUID) -> Bool {
        guard let profile = profiles.first(where: { $0.id == id }) else {
            reportActionProblem(SSHConnectionsProblem(
                kind: .connection,
                message: SSHConnectionsControllerError.profileNotFound(id).localizedDescription
            ))
            return false
        }

        do {
            try connectAction(profile)
            isPickerPresented = false
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

    private func persist(_ candidate: [SSHProfile]) throws {
        guard libraryIsLoaded else {
            throw SSHConnectionsControllerError.libraryUnavailable
        }
        let candidate = try SSHProfileStore.validated(candidate)

        do {
            try store.save(candidate)
        } catch {
            reportActionProblem(
                SSHConnectionsProblem(kind: .save, message: error.localizedDescription)
            )
            throw error
        }

        profiles = candidate
        if problem?.kind == .save { problem = nil }
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

    var errorDescription: String? {
        switch self {
        case .libraryUnavailable:
            return "Connections cannot be changed until the library loads successfully."
        case .profileNotFound:
            return "The selected connection no longer exists."
        }
    }
}
