import Foundation

public enum SSHCommandBuilder {
    public static let executable = "/usr/bin/ssh"

    public static func invocation(
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

    private static func expandHome(in path: String, homeDirectory: String) -> String {
        if path == "~" { return homeDirectory }
        if path.hasPrefix("~/") {
            return homeDirectory + String(path.dropFirst())
        }
        return path
    }
}
