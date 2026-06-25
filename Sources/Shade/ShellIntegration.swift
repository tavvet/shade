import Foundation

/// Opt-in zsh "shell enrichment": when enabled, Shade spawns the login shell
/// with `ZDOTDIR` pointed at a bundled shim directory so a thin/default zsh
/// gets real tab-completion (`compinit`) and Shade's OSC 133 marks — WITHOUT
/// editing any of the user's dotfiles. The shim sources the user's real startup
/// files first and only layers Shade's additions where they're absent (augment,
/// never override). See `integrations/zdotdir/` for the shell side.
///
/// Mechanism mirrors VS Code's terminal ZDOTDIR injection: we point `ZDOTDIR`
/// at our shim dir and remember the user's original in `SHADE_USER_ZDOTDIR`;
/// each shim chains the user's matching file then restores `ZDOTDIR` so the
/// next startup file still loads from ours.
enum ShellIntegration {

    /// zsh is the only shell we inject into. Shade spawns a *login* shell, where
    /// bash ignores `--rcfile` and `BASH_ENV` is non-interactive only — so
    /// bash/fish keep the manual `source` snippet (see README). zsh honours
    /// `ZDOTDIR` for login shells, which is what makes this clean and reversible.
    static func isSupported(shellName: String) -> Bool {
        shellName == "zsh"
    }

    /// The `ZDOTDIR` shim directory shipped read-only inside the bundle
    /// (`Contents/Resources/integrations/zdotdir`). The shims only ever *source*,
    /// so read-only is fine.
    static var shimDirectory: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("integrations/zdotdir", isDirectory: true)
    }

    /// Directory holding the OSC 133 snippets (`Contents/Resources/integrations`).
    static var integrationDirectory: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("integrations", isDirectory: true)
    }

    /// Environment array for `LocalProcessTerminalView.startProcess`, or `nil`
    /// to mean "use SwiftTerm's default" (today's behaviour) when the feature is
    /// off, the shell isn't zsh, or the bundled shim is missing.
    static func environment(shellName: String, enabled: Bool) -> [String]? {
        guard enabled, isSupported(shellName: shellName),
              let shim = shimDirectory, let integrations = integrationDirectory,
              // Guard against a missing/incomplete shim: pointing ZDOTDIR at a
              // dir with no .zshrc would make zsh skip the user's rc files too.
              FileManager.default.fileExists(atPath: shim.appendingPathComponent(".zshrc").path)
        else { return nil }

        return makeEnvironment(
            shimPath: shim.path,
            integrationPath: integrations.path,
            processEnv: ProcessInfo.processInfo.environment
        )
    }

    /// Pure builder (testable). SwiftTerm hands a non-nil `environment` straight
    /// to `execve`, replacing the child env — so we must pass a *complete* set.
    /// We replicate the same minimal vars SwiftTerm uses for `environment: nil`
    /// (TERM/COLORTERM/LANG + identity vars) and add only the ZDOTDIR wiring.
    /// We deliberately omit `PATH`: exactly as today, the login shell rebuilds
    /// it from `/etc/zprofile` (`path_helper`), which runs regardless of ZDOTDIR.
    static func makeEnvironment(shimPath: String,
                                integrationPath: String,
                                processEnv: [String: String]) -> [String] {
        var env: [String: String] = [
            "TERM": "xterm-256color",
            "COLORTERM": "truecolor",
            "LANG": "en_US.UTF-8",
        ]
        for key in ["LOGNAME", "USER", "HOME", "LC_CTYPE", "LC_ALL", "DISPLAY"] {
            if let value = processEnv[key] { env[key] = value }
        }

        let home = processEnv["HOME"] ?? NSHomeDirectory()
        env["ZDOTDIR"] = shimPath
        env["SHADE_USER_ZDOTDIR"] = processEnv["ZDOTDIR"] ?? home
        env["SHADE_INTEGRATION_DIR"] = integrationPath
        env["SHADE_INJECTION"] = "1"

        return env.map { "\($0.key)=\($0.value)" }.sorted()
    }
}
