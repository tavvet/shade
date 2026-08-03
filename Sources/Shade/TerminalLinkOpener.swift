import AppKit

/// Resolves terminal link text into an explicit system action. Resolution is
/// pure and testable; only `open` touches NSWorkspace.
enum TerminalLinkOpener {
    enum Target: Equatable {
        case reveal(URL)
        case open(URL)
    }

    static func resolve(
        _ rawLink: String,
        cwd: String,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> Target? {
        let link = rawLink.trimmingCharacters(in: .whitespaces)

        if let url = URL(string: link), url.isFileURL {
            return .reveal(url)
        }

        if link.hasPrefix("/") || link.hasPrefix("~") {
            let expanded = (link as NSString).expandingTildeInPath
            if fileExists(expanded) {
                return .reveal(URL(fileURLWithPath: expanded))
            }
        }

        if !link.isEmpty, !cwd.isEmpty, !link.contains("://"), !link.hasPrefix("/") {
            let candidate = (cwd as NSString).appendingPathComponent(link)
            if fileExists(candidate) {
                return .reveal(URL(fileURLWithPath: candidate))
            }
        }

        if let url = URL(string: link), url.scheme != nil {
            return .open(url)
        }
        return nil
    }

    @MainActor
    static func open(_ rawLink: String, cwd: String) {
        guard let target = resolve(rawLink, cwd: cwd) else { return }
        switch target {
        case .reveal(let url):
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case .open(let url):
            NSWorkspace.shared.open(url)
        }
    }
}
