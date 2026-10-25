/// An executable plus its argument boundaries. Terminal startup keeps this
/// structure intact through process creation, so values never become shell
/// syntax or startup input.
public struct ProcessInvocation: Equatable, Sendable {
    public let executable: String
    public let arguments: [String]
}
