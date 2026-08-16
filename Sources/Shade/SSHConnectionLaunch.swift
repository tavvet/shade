import Foundation

/// Adapts a validated SSH profile to the generic terminal-launch contract.
enum SSHConnectionLaunch {
    static func configuration(
        for profile: SSHProfile,
        homeDirectory: String = NSHomeDirectory()
    ) throws -> TerminalLaunchConfiguration {
        let profile = try profile.normalized()
        return TerminalLaunchConfiguration(
            title: profile.name,
            initialCommand: try SSHCommandBuilder.invocation(
                for: profile,
                homeDirectory: homeDirectory
            )
        )
    }
}
