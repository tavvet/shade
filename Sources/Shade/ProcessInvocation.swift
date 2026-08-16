/// An executable plus its argument boundaries. Terminal startup keeps this
/// structure intact through process creation, so values never become shell
/// syntax or startup input.
struct ProcessInvocation: Equatable, Sendable {
    let executable: String
    let arguments: [String]
}
