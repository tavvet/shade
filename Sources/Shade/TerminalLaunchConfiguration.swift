import Foundation

/// Describes how a new terminal tab should begin without coupling terminal
/// lifecycle code to a particular feature such as SSH or session restore.
struct TerminalLaunchConfiguration: Equatable, Sendable {
    var startupDirectory: String?
    var title: String?
    var initialCommand: ProcessInvocation?

    init(
        startupDirectory: String? = nil,
        title: String? = nil,
        initialCommand: ProcessInvocation? = nil
    ) {
        self.startupDirectory = startupDirectory
        self.title = title
        self.initialCommand = initialCommand
    }

    /// Bytes queued into the freshly started login shell. A carriage return is
    /// the terminal's normal Enter key, so the command is visible in shell
    /// history and returning from it leaves the local prompt alive.
    var initialInput: [UInt8]? {
        guard let initialCommand else { return nil }
        return Array((ShellCommandRenderer.render(initialCommand) + "\r").utf8)
    }
}
