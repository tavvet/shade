import Foundation

/// Stable token matching for the quick connection picker.
enum SSHConnectionPickerSearch {
    private static let invariantLocale = Locale(identifier: "en_US_POSIX")

    static func matches(
        _ profiles: [SSHProfile],
        query: String,
        locale: Locale = .current
    ) -> [SSHProfile] {
        let tokens = query
            .split(whereSeparator: { $0.isWhitespace })
            .map {
                SearchToken(
                    localized: normalized(String($0), locale: locale),
                    invariant: normalized(String($0), locale: invariantLocale)
                )
            }
        guard !tokens.isEmpty else { return profiles }

        return profiles.filter { profile in
            let searchableText = [
                profile.name,
                profile.host,
                profile.username,
                profile.port.map(String.init),
                profile.identityFile,
            ]
            .compactMap { $0 }
            .joined(separator: " ")
            let localizedSearchable = normalized(searchableText, locale: locale)
            let invariantSearchable = normalized(searchableText, locale: invariantLocale)
            return tokens.allSatisfy { token in
                localizedSearchable.contains(token.localized)
                    || invariantSearchable.contains(token.invariant)
            }
        }
    }

    private static func normalized(_ value: String, locale: Locale) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: locale
        )
    }

    private struct SearchToken {
        let localized: String
        let invariant: String
    }
}
