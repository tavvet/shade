import Foundation

/// Stable token matching for the quick connection picker.
enum SSHConnectionPickerSearch {
    static func matches(_ profiles: [SSHProfile], query: String) -> [SSHProfile] {
        let tokens = query
            .split(whereSeparator: { $0.isWhitespace })
            .map { normalized(String($0)) }
        guard !tokens.isEmpty else { return profiles }

        return profiles.filter { profile in
            let searchable = normalized([
                profile.name,
                profile.host,
                profile.username,
                profile.port.map(String.init),
                profile.identityFile,
            ]
            .compactMap { $0 }
            .joined(separator: " "))
            return tokens.allSatisfy(searchable.contains)
        }
    }

    private static func normalized(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
    }
}
