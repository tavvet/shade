import Foundation
import ShadeCore

protocol SSHProfileStoring {
    @MainActor
    func load() async throws -> [SSHProfile]
    @MainActor
    func save(_ profiles: [SSHProfile]) async throws
    @MainActor
    func save(_ profiles: [SSHProfile], replacing previous: [SSHProfile]) async throws
}

extension SSHProfileStoring {
    @MainActor
    func save(_ profiles: [SSHProfile], replacing previous: [SSHProfile]) async throws {
        try await save(profiles)
    }
}

/// Persists ordered SSH profiles separately from scalar application preferences.
/// The versioned envelope leaves room for future migrations without coupling
/// connection data to `PreferencesStore` or UserDefaults.
struct SSHProfileStore: Sendable {
    static let currentVersion = 1
    private static let comparisonLocale = Locale(identifier: "en_US_POSIX")

    let fileURL: URL

    init(fileURL: URL = Self.defaultFileURL()) {
        self.fileURL = fileURL
    }

    nonisolated func load() throws -> [SSHProfile] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }

        let data = try Data(contentsOf: fileURL)
        return try Self.decode(data)
    }

    static func decode(_ data: Data) throws -> [SSHProfile] {
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.version == Self.currentVersion else {
            throw SSHProfileStoreError.unsupportedVersion(envelope.version)
        }
        return try Self.validated(envelope.profiles)
    }

    nonisolated func save(_ profiles: [SSHProfile]) throws {
        let data = try Self.encode(profiles)

        let fileManager = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        try ConfigurationFileIO.replace(data, at: fileURL)
    }

    static func encode(_ profiles: [SSHProfile]) throws -> Data {
        let validated = try Self.validated(profiles)
        let envelope = Envelope(version: Self.currentVersion, profiles: validated)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(envelope)
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

    static func validated(_ profiles: [SSHProfile]) throws -> [SSHProfile] {
        let normalized = try profiles.map { try $0.normalized() }
        var ids = Set<UUID>()
        var names = Set<String>()

        for profile in normalized {
            guard ids.insert(profile.id).inserted else {
                throw SSHProfileStoreError.duplicateID(profile.id)
            }
            let comparisonName = profile.name.folding(
                options: [.caseInsensitive],
                locale: comparisonLocale
            )
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

extension SSHProfileStore: SSHProfileStoring {
    func load() async throws -> [SSHProfile] {
        try await ConfigurationDisk.run { try self.load() }
    }

    func save(_ profiles: [SSHProfile]) async throws {
        try await ConfigurationDisk.run { try self.save(profiles) }
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
