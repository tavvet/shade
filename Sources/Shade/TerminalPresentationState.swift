import Foundation

/// User-visible state for one terminal tab. It owns title precedence and the
/// activity/failure indicators, but has no dependency on AppKit or SwiftTerm.
final class TerminalPresentationState {
    let shellName: String
    var onChange: (() -> Void)?

    private(set) var oscTitle = ""
    private(set) var userTitle: String?
    private(set) var lastExitCode: Int?
    private(set) var hasUnseenActivity = false
    private(set) var isActive = false

    init(shellName: String) {
        self.shellName = shellName
    }

    func displayTitle(remoteIndicator: String?, cwd: String) -> String {
        Self.resolveDisplayTitle(
            userTitle: userTitle,
            remoteIndicator: remoteIndicator,
            oscTitle: oscTitle,
            cwd: cwd.isEmpty ? nil : Self.abbreviateHome(cwd),
            shellName: shellName
        )
    }

    func setOscTitle(_ value: String) {
        guard value != oscTitle else { return }
        oscTitle = value
        onChange?()
    }

    func setUserTitle(_ raw: String) {
        let value = Self.normalizedUserTitle(raw)
        guard value != userTitle else { return }
        userTitle = value
        onChange?()
    }

    func setLastExitCode(_ value: Int?) {
        guard value != lastExitCode else { return }
        lastExitCode = value
        onChange?()
    }

    /// Updates visibility and marks accumulated background output as read when
    /// the tab becomes active.
    func setActive(_ active: Bool) {
        isActive = active
        if active, hasUnseenActivity {
            hasUnseenActivity = false
            onChange?()
        }
    }

    /// Records output only for a background tab; repeated writes coalesce into
    /// one state change until the tab is activated again.
    func noteActivity() {
        guard !isActive, !hasUnseenActivity else { return }
        hasUnseenActivity = true
        onChange?()
    }

    static func resolveDisplayTitle(
        userTitle: String?,
        remoteIndicator: String?,
        oscTitle: String,
        cwd: String?,
        shellName: String
    ) -> String {
        if let userTitle, !userTitle.isEmpty { return userTitle }
        if let remoteIndicator { return "[\(remoteIndicator)]" }
        if !oscTitle.isEmpty { return oscTitle }
        if let cwd, !cwd.isEmpty { return cwd }
        return shellName
    }

    static func normalizedUserTitle(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func abbreviateHome(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}
