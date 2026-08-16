import Foundation

/// A user-named preset for an interactive OpenSSH connection.
///
/// `host` may be either a hostname/IP address or an alias from `~/.ssh/config`.
/// Optional values override the corresponding OpenSSH configuration only for
/// this connection. Passwords and private-key contents never belong here.
struct SSHProfile: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var host: String
    var username: String?
    var port: Int?
    var identityFile: String?

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        username: String? = nil,
        port: Int? = nil,
        identityFile: String? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.username = username
        self.port = port
        self.identityFile = identityFile
    }

    /// Returns the canonical persisted form or throws before invalid input can
    /// reach OpenSSH. Trimming optional blank values to nil keeps the JSON and
    /// command builder deterministic.
    func normalized() throws -> SSHProfile {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedUsername = Self.normalizedOptional(username)
        let normalizedIdentityFile = Self.normalizedOptional(identityFile)

        guard !normalizedName.isEmpty else {
            throw SSHProfileValidationError.nameRequired
        }
        try Self.rejectControlCharacters(in: normalizedName, field: .name)

        guard !normalizedHost.isEmpty else {
            throw SSHProfileValidationError.hostRequired
        }
        try Self.rejectControlCharacters(in: normalizedHost, field: .host)
        guard !normalizedHost.hasPrefix("-") else {
            throw SSHProfileValidationError.hostStartsWithDash
        }
        guard normalizedHost.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            throw SSHProfileValidationError.hostContainsWhitespace
        }

        if let normalizedUsername {
            try Self.rejectControlCharacters(in: normalizedUsername, field: .username)
            guard normalizedUsername.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
                throw SSHProfileValidationError.usernameContainsWhitespace
            }
        }

        if let normalizedIdentityFile {
            try Self.rejectControlCharacters(in: normalizedIdentityFile, field: .identityFile)
        }

        if let port, !(1...65_535).contains(port) {
            throw SSHProfileValidationError.invalidPort(port)
        }

        return SSHProfile(
            id: id,
            name: normalizedName,
            host: normalizedHost,
            username: normalizedUsername,
            port: port,
            identityFile: normalizedIdentityFile
        )
    }

    private static func normalizedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func rejectControlCharacters(
        in value: String,
        field: SSHProfileField
    ) throws {
        if value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) {
            throw SSHProfileValidationError.controlCharacters(field)
        }
    }
}

enum SSHProfileField: String, Equatable, Sendable {
    case name
    case host
    case username
    case identityFile
}

enum SSHProfileValidationError: Error, Equatable, LocalizedError {
    case nameRequired
    case hostRequired
    case hostStartsWithDash
    case hostContainsWhitespace
    case usernameContainsWhitespace
    case invalidPort(Int)
    case controlCharacters(SSHProfileField)

    var errorDescription: String? {
        switch self {
        case .nameRequired:
            return "Connection name is required."
        case .hostRequired:
            return "Host or SSH config alias is required."
        case .hostStartsWithDash:
            return "Host cannot start with a dash."
        case .hostContainsWhitespace:
            return "Host cannot contain whitespace."
        case .usernameContainsWhitespace:
            return "Username cannot contain whitespace."
        case .invalidPort(let port):
            return "Port \(port) is outside the valid range 1...65535."
        case .controlCharacters(let field):
            return "\(field.rawValue) cannot contain control characters."
        }
    }
}
