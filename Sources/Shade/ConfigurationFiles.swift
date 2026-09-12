import Foundation

struct ConfigurationFiles: Sendable {
    enum Contents: Sendable { case empty, existing }

    struct Snapshot: Sendable {
        let preferences: Preferences
        let profiles: [SSHProfile]
    }

    let directory: URL
    var settingsURL: URL { directory.appendingPathComponent("settings.json") }
    var connectionsURL: URL { directory.appendingPathComponent("connections.json") }

    func inspect() throws -> Contents {
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else { throw ConfigurationError.notDirectory }
        // resourceValues throws for access errors; only an actual absent file
        // may be treated as an empty destination.
        let settings = try exists(settingsURL)
        let connections = try exists(connectionsURL)
        guard settings == connections else { throw ConfigurationError.incompleteFolder }
        if settings {
            _ = try load()
            return .existing
        }
        return .empty
    }

    func load() throws -> Snapshot {
        Snapshot(preferences: try SettingsFileDocument.decode(ConfigurationFileIO.read(at: settingsURL)),
                 profiles: try SSHProfileStore.decode(ConfigurationFileIO.read(at: connectionsURL)))
    }

    func create(_ snapshot: Snapshot) throws {
        guard try inspect() == .empty else { throw ConfigurationError.destinationNotEmpty }
        let settings = try SettingsFileDocument.encode(snapshot.preferences)
        let connections = try SSHProfileStore.encode(snapshot.profiles)
        try ConfigurationFileIO.validateSize(settings, at: settingsURL)
        try ConfigurationFileIO.validateSize(connections, at: connectionsURL)
        // Never replace a destination, even if another process creates it
        // after inspection. A partial copy is not activated and is left visible
        // for recovery instead of risking deletion of another writer's data.
        try ConfigurationFileIO.replace(settings, at: settingsURL, allowOverwrite: false)
        try ConfigurationFileIO.replace(connections, at: connectionsURL, allowOverwrite: false)
    }

    private func exists(_ url: URL) throws -> Bool {
        do {
            _ = try url.resourceValues(forKeys: [.isRegularFileKey])
            return true
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return false
        }
    }
}

enum ConfigurationError: LocalizedError {
    case invalidFile(String)
    case unsupportedSettingsVersion(Int)
    case invalidPreferences
    case incompleteFolder
    case notDirectory
    case destinationNotEmpty
    case useLocalStorage
    case changedExternally
    case downloadRequired(String)
    case fileTooLarge(String)

    var errorDescription: String? {
        switch self {
        case .invalidFile(let name):
            return "\(name) must be a regular file no larger than 5 MB, not a symbolic link."
        case .unsupportedSettingsVersion(let version):
            return "Settings file version \(version) is not supported."
        case .invalidPreferences:
            return "The settings file contains invalid or out-of-range values."
        case .incompleteFolder:
            return "The folder must contain both settings.json and connections.json, or neither. Wait for both files to download, or choose an empty folder."
        case .notDirectory:
            return "Choose a directory for the configuration files."
        case .destinationNotEmpty:
            return "Configuration files already exist in this folder. They have not been overwritten."
        case .useLocalStorage:
            return "This is Shade's local storage folder. Use Local Storage instead."
        case .changedExternally:
            return "The configuration changed outside Shade. Reload it before trying this change again."
        case .downloadRequired(let name):
            return "\(name) is not downloaded from iCloud Drive. Download it in Finder (or choose Keep Downloaded), then reload."
        case .fileTooLarge(let name):
            return "\(name) exceeds the 5 MB limit. The existing configuration has not been replaced."
        }
    }
}
