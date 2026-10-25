import Foundation
import ShadeCore

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
