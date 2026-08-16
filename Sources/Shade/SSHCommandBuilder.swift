import Foundation

/// An executable plus its argument boundaries, kept structured until the final
/// shell-rendering step so profile values are never concatenated as raw syntax.
struct ProcessInvocation: Equatable, Sendable {
    let executable: String
    let arguments: [String]
}

enum SSHCommandBuilder {
    static let executable = "/usr/bin/ssh"

    static func invocation(
        for profile: SSHProfile,
        homeDirectory: String = NSHomeDirectory()
    ) throws -> ProcessInvocation {
        let profile = try profile.normalized()
        var arguments: [String] = []

        if let port = profile.port {
            arguments.append(contentsOf: ["-p", String(port)])
        }
        if let username = profile.username {
            arguments.append(contentsOf: ["-l", username])
        }
        if let identityFile = profile.identityFile {
            arguments.append(contentsOf: [
                "-i",
                expandHome(in: identityFile, homeDirectory: homeDirectory),
            ])
        }
        arguments.append(profile.host)

        return ProcessInvocation(executable: executable, arguments: arguments)
    }

    static func shellCommand(
        for profile: SSHProfile,
        homeDirectory: String = NSHomeDirectory()
    ) throws -> String {
        ShellCommandRenderer.render(
            try invocation(for: profile, homeDirectory: homeDirectory)
        )
    }

    private static func expandHome(in path: String, homeDirectory: String) -> String {
        if path == "~" { return homeDirectory }
        if path.hasPrefix("~/") {
            return homeDirectory + String(path.dropFirst())
        }
        return path
    }
}

enum ShellCommandRenderer {
    private static let unquotedCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_@%+=:,./-"
    )

    static func render(_ invocation: ProcessInvocation) -> String {
        ([invocation.executable] + invocation.arguments)
            .map(quote)
            .joined(separator: " ")
    }

    static func quote(_ argument: String) -> String {
        guard !argument.isEmpty,
              argument.unicodeScalars.allSatisfy(unquotedCharacters.contains) else {
            return "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        return argument
    }
}
