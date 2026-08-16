import Foundation

/// Persists ordered SSH profiles separately from scalar application preferences.
/// The versioned envelope leaves room for future migrations without coupling
/// connection data to `PreferencesStore` or UserDefaults.
struct SSHProfileStore {
    static let currentVersion = 1

    let fileURL: URL

    init(fileURL: URL = Self.defaultFileURL()) {
        self.fileURL = fileURL
    }

    func load() throws -> [SSHProfile] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }

        let data = try Data(contentsOf: fileURL)
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.version == Self.currentVersion else {
            throw SSHProfileStoreError.unsupportedVersion(envelope.version)
        }
        return try Self.validate(envelope.profiles)
    }

    func save(_ profiles: [SSHProfile]) throws {
        let validated = try Self.validate(profiles)
        let envelope = Envelope(version: Self.currentVersion, profiles: validated)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(envelope)

        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("Shade", isDirectory: true)
            .appendingPathComponent("connections.json", isDirectory: false)
    }

    private static func validate(_ profiles: [SSHProfile]) throws -> [SSHProfile] {
        let normalized = try profiles.map { try $0.normalized() }
        var ids = Set<UUID>()
        var names = Set<String>()

        for profile in normalized {
            guard ids.insert(profile.id).inserted else {
                throw SSHProfileStoreError.duplicateID(profile.id)
            }
            let comparisonName = profile.name.lowercased()
            guard names.insert(comparisonName).inserted else {
                throw SSHProfileStoreError.duplicateName(profile.name)
            }
        }
        return normalized
    }

    private struct Envelope: Codable {
        let version: Int
        let profiles: [SSHProfile]
    }
}

enum SSHProfileStoreError: Error, Equatable, LocalizedError {
    case unsupportedVersion(Int)
    case duplicateID(UUID)
    case duplicateName(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "Connections file version \(version) is not supported."
        case .duplicateID:
            return "Connections contain duplicate identifiers."
        case .duplicateName(let name):
            return "A connection named \"\(name)\" already exists."
        }
    }
}
