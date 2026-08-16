import Foundation

protocol SSHProfileStoring {
    func load() throws -> [SSHProfile]
    func save(_ profiles: [SSHProfile]) throws
}

/// Persists ordered SSH profiles separately from scalar application preferences.
/// The versioned envelope leaves room for future migrations without coupling
/// connection data to `PreferencesStore` or UserDefaults.
struct SSHProfileStore {
    static let currentVersion = 1
    private static let comparisonLocale = Locale(identifier: "en_US_POSIX")

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
        return try Self.validated(envelope.profiles)
    }

    func save(_ profiles: [SSHProfile]) throws {
        let validated = try Self.validated(profiles)
        let envelope = Envelope(version: Self.currentVersion, profiles: validated)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(envelope)

        let fileManager = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        // Prepare and secure a sibling file before replacing the live library.
        // There are no throwing operations after the final move/replace, so a
        // reported save failure can never leave newer data on disk than the
        // controller has published in memory.
        let temporaryURL = directory.appendingPathComponent(
            ".connections-\(UUID().uuidString).tmp",
            isDirectory: false
        )
        defer { try? fileManager.removeItem(at: temporaryURL) }

        guard fileManager.createFile(
            atPath: temporaryURL.path,
            contents: data,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw CocoaError(
                .fileWriteUnknown,
                userInfo: [NSFilePathErrorKey: temporaryURL.path]
            )
        }

        if fileManager.fileExists(atPath: fileURL.path) {
            _ = try fileManager.replaceItemAt(
                fileURL,
                withItemAt: temporaryURL,
                backupItemName: nil,
                options: .usingNewMetadataOnly
            )
        } else {
            try fileManager.moveItem(at: temporaryURL, to: fileURL)
        }
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

extension SSHProfileStore: SSHProfileStoring {}

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
