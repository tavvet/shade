import Foundation

/// An executable plus its argument boundaries, kept structured until the final
/// shell-rendering step so feature values are never concatenated as raw syntax.
struct ProcessInvocation: Equatable, Sendable {
    let executable: String
    let arguments: [String]
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
