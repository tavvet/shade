import Combine
import Foundation

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
    private var snapshot: ConfigurationFiles.Snapshot

    init(userDefaults: UserDefaults = .standard,
         localConnectionsURL: URL = SSHProfileStore.defaultFileURL()) {
        self.userDefaults = userDefaults
        self.localConnectionsURL = localConnectionsURL
        localPreferences = PreferencesStore(userDefaults: userDefaults)
        snapshot = .init(preferences: localPreferences.load(), profiles: [])
        if let path = userDefaults.string(forKey: Self.directoryKey) {
            directory = URL(fileURLWithPath: path, isDirectory: true)
        }
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
                        let files = ConfigurationFiles(directory: directory)
                        let current = try files.load()
                        let data = try SettingsFileDocument.encode(preferences)
                        try ConfigurationFileIO.update(at: files.settingsURL) { url in
                            let stored = try SettingsFileDocument.decode(ConfigurationFileIO.readUncoordinated(at: url))
                            guard stored == previous else { throw ConfigurationError.changedExternally }
                            try ConfigurationFileIO.replace(data, at: url)
                        }
                        return ConfigurationFiles.Snapshot(preferences: preferences, profiles: current.profiles)
                    }
                    self.accept(loaded, announcePreferences: false)
                } else {
                    try self.localPreferences.save(preferences, replacing: previous)
                    self.snapshot = .init(preferences: preferences, profiles: self.snapshot.profiles)
                    self.setProblem(nil)
                }
            } catch {
                self.setProblem(error.localizedDescription)
                throw error
            }
        }
    }

    /// Saves keyboard font zoom and announces it, so observers apply the size
    /// from the same store that persisted it.
    func saveFontSize(_ fontSize: CGFloat) async throws {
        let revision = locationRevision
        if directory == nil {
            try await write {
                guard revision == self.locationRevision else { throw ConfigurationError.changedExternally }
                self.localPreferences.saveFontSize(fontSize)
            }
        } else {
            let previous = await reload()
            guard revision == locationRevision else { throw ConfigurationError.changedExternally }
            var updated = previous
            updated.fontSize = fontSize
            try await save(updated, replacing: previous)
        }
        NotificationCenter.default.post(name: .shadePreferencesChanged, object: self)
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
            self.accept(loaded, announcePreferences: false)
            self.notifyChange()
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
            self.accept(.init(preferences: self.localPreferences.load(), profiles: profiles), announcePreferences: false)
            self.notifyChange()
        }
    }

    func reloadFromDisk() async {
        _ = await reload()
        notifyChange()
    }

    /// Quitting waits for accepted writes, but not for an unrelated background
    /// refresh stalled in a file provider.
    func waitForPendingWrites() async {
        await lastWrite?.value
    }

    private func write(_ operation: @escaping @MainActor () async throws -> Void) async throws {
        let task = operations.enqueue(operation)
        lastWrite = Task { _ = await task.result }
        try await task.value
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

    private func accept(_ loaded: ConfigurationFiles.Snapshot, announcePreferences: Bool = true) {
        let changed = snapshot.preferences != loaded.preferences
        snapshot = loaded
        setProblem(nil)
        if changed, announcePreferences {
            NotificationCenter.default.post(name: .shadePreferencesChanged, object: self)
        }
    }

    private func setProblem(_ message: String?) {
        if problem != message { problem = message }
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: Self.didChange, object: self)
        NotificationCenter.default.post(name: .shadePreferencesChanged, object: self)
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
