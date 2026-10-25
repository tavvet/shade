import Combine
import Foundation
import ShadeCore

extension Notification.Name {
    /// Posted only by `ConfigurationStore` (through its
    /// `PreferencesChangeAnnouncer`), with the store as the object.
    static let shadePreferencesChanged = Notification.Name("ShadePreferencesChanged")
}

/// The device-local location selects a backend. Runtime readers use the last
/// valid snapshot; explicit refreshes and mutations perform disk I/O off-main.
@MainActor
final class ConfigurationStore: ObservableObject, PreferencesStoring {
    static let shared = ConfigurationStore()
    static let directoryKey = "configurationDirectory"
    static let didChange = Notification.Name("ShadeConfigurationChanged")

    @Published private(set) var directory: URL?
    @Published private(set) var problem: String?
    @Published private(set) var isChangingLocation = false
    private var lastWrite: Task<Void, Never>?

    let localConnectionsURL: URL
    private let userDefaults: UserDefaults
    private let localPreferences: PreferencesStore
    private let operations = ConfigurationTaskQueue()
    private var locationRevision = 0
    /// The preferences last announced to observers, plus the cached profiles.
    private var snapshot: ConfigurationFiles.Snapshot
    private var announcer: PreferencesChangeAnnouncer!

    /// `announcementInterval` spaces announcements during bursts such as
    /// slider drags; a single change is still announced immediately.
    init(userDefaults: UserDefaults = .standard,
         localConnectionsURL: URL = SSHProfileStore.defaultFileURL(),
         announcementInterval: Duration = .milliseconds(120)) {
        self.userDefaults = userDefaults
        self.localConnectionsURL = localConnectionsURL
        localPreferences = PreferencesStore(userDefaults: userDefaults)
        snapshot = .init(preferences: localPreferences.load(), profiles: [])
        if let path = userDefaults.string(forKey: Self.directoryKey) {
            directory = URL(fileURLWithPath: path, isDirectory: true)
        }
        announcer = PreferencesChangeAnnouncer(interval: announcementInterval) { [weak self] in
            guard let self else { return }
            NotificationCenter.default.post(name: .shadePreferencesChanged, object: self)
        }
    }

    /// Lets observers tell this store's announcements apart from others'.
    var preferencesChangeSender: AnyObject? { self }

    /// Waits until a scheduled `.shadePreferencesChanged` has been posted.
    func waitForPendingAnnouncement() async {
        await announcer.waitForPending()
    }

    func load() -> Preferences {
        directory == nil ? localPreferences.load() : snapshot.preferences
    }

    func reload() async -> Preferences {
        do {
            return try await operations.run {
                do {
                    self.accept(try await self.readCurrent())
                } catch {
                    self.setProblem(error.localizedDescription)
                }
                return self.load()
            }
        } catch {
            return load()
        }
    }

    func loadProfiles() async throws -> [SSHProfile] {
        try await operations.run {
            do {
                let loaded = try await self.readCurrent()
                self.accept(loaded)
                return loaded.profiles
            } catch {
                self.setProblem(error.localizedDescription)
                throw error
            }
        }
    }

    func save(_ preferences: Preferences, replacing previous: Preferences) async throws {
        let revision = locationRevision
        try await write {
            guard revision == self.locationRevision else { throw ConfigurationError.changedExternally }
            do {
                if let directory = self.directory {
                    let loaded = try await ConfigurationDisk.run {
                        try Self.updateSettings(in: ConfigurationFiles(directory: directory)) { stored in
                            guard stored == previous else { throw ConfigurationError.changedExternally }
                            return preferences
                        }
                    }
                    self.accept(loaded)
                } else {
                    try self.localPreferences.save(preferences, replacing: previous)
                    self.accept(.init(preferences: preferences, profiles: self.snapshot.profiles))
                }
            } catch {
                self.setProblem(error.localizedDescription)
                throw error
            }
        }
    }

    /// Reads the stored font size, applies `transform`, clamps the result to the
    /// supported range and saves it in one storage transaction, so keyboard zoom
    /// never computes from a value read in an earlier transaction. Returns the
    /// stored size afterwards.
    @discardableResult
    func updateFontSize(
        _ transform: @escaping @Sendable (CGFloat) -> CGFloat
    ) async throws -> CGFloat {
        let revision = locationRevision
        return try await write {
            guard revision == self.locationRevision else { throw ConfigurationError.changedExternally }
            do {
                if let directory = self.directory {
                    let loaded = try await ConfigurationDisk.run {
                        try Self.updateSettings(in: ConfigurationFiles(directory: directory)) { stored in
                            var updated = stored
                            updated.fontSize = Preferences.clampFontSize(transform(stored.fontSize))
                            return updated
                        }
                    }
                    self.accept(loaded)
                    return loaded.preferences.fontSize
                }
                let target = self.localPreferences.updateFontSize(transform)
                self.accept(.init(preferences: self.localPreferences.load(), profiles: self.snapshot.profiles))
                return target
            } catch {
                self.setProblem(error.localizedDescription)
                throw error
            }
        }
    }

    /// Applies `change` to settings.json inside one coordinated write: the
    /// stored document is read, changed and replaced only if the result differs.
    /// The portable pair must stay valid, so connections.json is decoded first
    /// and a missing or invalid file blocks the write. Returns the new snapshot.
    nonisolated private static func updateSettings(
        in files: ConfigurationFiles,
        _ change: (Preferences) throws -> Preferences
    ) throws -> ConfigurationFiles.Snapshot {
        let profiles = try SSHProfileStore.decode(ConfigurationFileIO.read(at: files.connectionsURL))
        let preferences = try ConfigurationFileIO.update(at: files.settingsURL) { url in
            let stored = try SettingsFileDocument.decode(ConfigurationFileIO.readUncoordinated(at: url))
            let updated = try change(stored)
            guard updated != stored else { return stored }
            try ConfigurationFileIO.replace(SettingsFileDocument.encode(updated), at: url)
            return updated
        }
        return ConfigurationFiles.Snapshot(preferences: preferences, profiles: profiles)
    }

    func saveProfiles(_ profiles: [SSHProfile], replacing previous: [SSHProfile]) async throws {
        let revision = locationRevision
        try await write {
            guard revision == self.locationRevision else { throw ConfigurationError.changedExternally }
            do {
                let directory = self.directory
                let localURL = self.localConnectionsURL
                let localPreferences = self.localPreferences.load()
                let loaded = try await ConfigurationDisk.run {
                    if let directory {
                        let files = ConfigurationFiles(directory: directory)
                        let current = try files.load()
                        let data = try SSHProfileStore.encode(profiles)
                        try ConfigurationFileIO.update(at: files.connectionsURL) { url in
                            let stored = try SSHProfileStore.decode(ConfigurationFileIO.readUncoordinated(at: url))
                            guard stored == previous else { throw ConfigurationError.changedExternally }
                            try ConfigurationFileIO.replace(data, at: url)
                        }
                        return ConfigurationFiles.Snapshot(preferences: current.preferences, profiles: profiles)
                    }
                    // A cached list from another location (or before an external
                    // edit) must not replace the preserved local library.
                    let stored = try SSHProfileStore(fileURL: localURL).load()
                    guard stored == previous else { throw ConfigurationError.changedExternally }
                    try SSHProfileStore(fileURL: localURL).save(profiles)
                    return ConfigurationFiles.Snapshot(preferences: localPreferences, profiles: profiles)
                }
                self.accept(loaded)
            } catch {
                self.setProblem(error.localizedDescription)
                throw error
            }
        }
    }

    /// Inspection is read-only, including canonicalization of provider paths.
    func inspectFolder(_ url: URL) async throws -> ConfigurationFiles.Contents {
        let localURL = localConnectionsURL
        return try await ConfigurationDisk.run {
            let folder = try Self.canonicalFolder(url, localConnectionsURL: localURL)
            return try ConfigurationFiles(directory: folder).inspect()
        }
    }

    func useFolder(_ url: URL, copyCurrent: Bool) async throws {
        guard !isChangingLocation else { throw ConfigurationError.changedExternally }
        isChangingLocation = true
        defer { isChangingLocation = false }
        try await write {
            let localURL = self.localConnectionsURL
            let source = self.directory
            let localPreferences = self.localPreferences.load()
            let (canonical, loaded) = try await ConfigurationDisk.run {
                let canonical = try Self.canonicalFolder(url, localConnectionsURL: localURL)
                let files = ConfigurationFiles(directory: canonical)
                let contents = try files.inspect()
                if copyCurrent {
                    guard contents == .empty else { throw ConfigurationError.destinationNotEmpty }
                    let current = try source.map { try ConfigurationFiles(directory: $0).load() }
                        ?? .init(preferences: localPreferences, profiles: SSHProfileStore(fileURL: localURL).load())
                    try files.create(current)
                } else {
                    guard contents == .existing else { throw ConfigurationError.incompleteFolder }
                }
                return (canonical, try files.load())
            }
            // Commit the pointer only after both documents are complete and valid.
            self.userDefaults.set(canonical.path, forKey: Self.directoryKey)
            self.directory = canonical
            self.locationRevision &+= 1
            self.accept(loaded)
            self.notifyLocationChange()
        }
    }

    /// Restore the preserved local data, without copying custom changes back.
    func useLocalStorage() async throws {
        guard !isChangingLocation else { throw ConfigurationError.changedExternally }
        isChangingLocation = true
        defer { isChangingLocation = false }
        try await write {
            let localURL = self.localConnectionsURL
            let profiles = try await ConfigurationDisk.run { try SSHProfileStore(fileURL: localURL).load() }
            self.userDefaults.removeObject(forKey: Self.directoryKey)
            self.directory = nil
            self.locationRevision &+= 1
            self.accept(.init(preferences: self.localPreferences.load(), profiles: profiles))
            self.notifyLocationChange()
        }
    }

    /// Re-reads both files. Preferences are announced only if they changed;
    /// `didChange` always prompts the connection library to reload.
    func reloadFromDisk() async {
        _ = await reload()
        notifyLocationChange()
    }

    /// Quitting waits for accepted writes, but not for an unrelated background
    /// refresh stalled in a file provider.
    func waitForPendingWrites() async {
        await lastWrite?.value
    }

    private func write<Value: Sendable>(
        _ operation: @escaping @MainActor () async throws -> Value
    ) async throws -> Value {
        let task = operations.enqueue(operation)
        lastWrite = Task { _ = await task.result }
        return try await task.value
    }

    private func readCurrent() async throws -> ConfigurationFiles.Snapshot {
        let directory = directory
        let localURL = localConnectionsURL
        let preferences = localPreferences.load()
        return try await ConfigurationDisk.run {
            if let directory { return try ConfigurationFiles(directory: directory).load() }
            return try .init(preferences: preferences, profiles: SSHProfileStore(fileURL: localURL).load())
        }
    }

    nonisolated private static func canonicalFolder(_ url: URL, localConnectionsURL: URL) throws -> URL {
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        guard canonical != localConnectionsURL.deletingLastPathComponent()
            .standardizedFileURL.resolvingSymlinksInPath() else { throw ConfigurationError.useLocalStorage }
        return canonical
    }

    /// The single path for publishing new values. `.shadePreferencesChanged` is
    /// requested only when the preferences differ from the last announced
    /// snapshot, and it is posted after the current storage transaction.
    private func accept(_ loaded: ConfigurationFiles.Snapshot) {
        let changed = snapshot.preferences != loaded.preferences
        snapshot = loaded
        setProblem(nil)
        if changed { announcer.request() }
    }

    private func setProblem(_ message: String?) {
        if problem != message { problem = message }
    }

    /// The storage location or file contents were replaced; preferences are
    /// announced separately by `accept` when they actually differ.
    private func notifyLocationChange() {
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}

@MainActor
struct ConfigurationSSHProfileStore: SSHProfileStoring {
    let configuration: ConfigurationStore

    func load() async throws -> [SSHProfile] { try await configuration.loadProfiles() }

    func save(_ profiles: [SSHProfile]) async throws {
        try await save(profiles, replacing: load())
    }

    func save(_ profiles: [SSHProfile], replacing previous: [SSHProfile]) async throws {
        try await configuration.saveProfiles(profiles, replacing: previous)
    }
}
