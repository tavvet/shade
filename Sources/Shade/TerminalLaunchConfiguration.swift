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
}
