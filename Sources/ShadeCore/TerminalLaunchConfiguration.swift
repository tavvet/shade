import Foundation

/// Describes how a new terminal tab should begin without coupling terminal
/// lifecycle code to a particular feature such as SSH or session restore.
public struct TerminalLaunchConfiguration: Equatable, Sendable {
    public var startupDirectory: String?
    public var title: String?
    public var initialCommand: ProcessInvocation?

    public init(
        startupDirectory: String? = nil,
        title: String? = nil,
        initialCommand: ProcessInvocation? = nil
    ) {
        self.startupDirectory = startupDirectory
        self.title = title
        self.initialCommand = initialCommand
    }
}
