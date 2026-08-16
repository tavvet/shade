import Foundation

/// Runs a configured command and the tab's login shell under one PTY-owning
/// process. The static wrapper script receives every executable and argument
/// positionally, so profile values never become shell syntax.
enum TerminalCommandSequence {
    static let wrapperExecutable = "/bin/sh"
    static let defaultExecutablePath = "/usr/bin:/bin:/usr/sbin:/sbin"
    private static let integrationMarker = "SHADE_SEQUENCE_HAS_INTEGRATION"
    private static let integrationKeys: Set<String> = [
        "ZDOTDIR",
        "SHADE_SHIM_ZDOTDIR",
        "SHADE_USER_ZDOTDIR",
        "SHADE_USER_ZDOTDIR_SET",
        "SHADE_INTEGRATION_DIR",
        "SHADE_INJECTION",
    ]

    /// `/bin/sh -c` uses the first argument after the script as `$0`; the login
    /// shell begins at `$1`, followed by the fully structured command invocation.
    /// Shell-integration variables are hidden from the configured command and
    /// restored only when the wrapper becomes the local login shell.
    static let wrapperScript = """
    login_shell=$1
    shift

    shade_sequence_has_integration=${SHADE_SEQUENCE_HAS_INTEGRATION-}
    if [ "$shade_sequence_has_integration" = 1 ]; then
        shade_zdotdir=$ZDOTDIR
        shade_shim_zdotdir=$SHADE_SHIM_ZDOTDIR
        shade_user_zdotdir=$SHADE_USER_ZDOTDIR
        shade_user_zdotdir_set=$SHADE_USER_ZDOTDIR_SET
        shade_integration_dir=$SHADE_INTEGRATION_DIR
        shade_injection=$SHADE_INJECTION

        if [ "$shade_user_zdotdir_set" = 1 ]; then
            ZDOTDIR=$shade_user_zdotdir
            export ZDOTDIR
        else
            unset ZDOTDIR
        fi
        unset SHADE_SHIM_ZDOTDIR SHADE_USER_ZDOTDIR SHADE_USER_ZDOTDIR_SET
        unset SHADE_INTEGRATION_DIR SHADE_INJECTION SHADE_SEQUENCE_HAS_INTEGRATION
    fi

    "$@"

    if [ "$shade_sequence_has_integration" = 1 ]; then
        ZDOTDIR=$shade_zdotdir
        SHADE_SHIM_ZDOTDIR=$shade_shim_zdotdir
        SHADE_USER_ZDOTDIR=$shade_user_zdotdir
        SHADE_USER_ZDOTDIR_SET=$shade_user_zdotdir_set
        SHADE_INTEGRATION_DIR=$shade_integration_dir
        SHADE_INJECTION=$shade_injection
        export ZDOTDIR SHADE_SHIM_ZDOTDIR SHADE_USER_ZDOTDIR
        export SHADE_USER_ZDOTDIR_SET SHADE_INTEGRATION_DIR SHADE_INJECTION
    fi
    exec "$login_shell" -l
    """

    static func invocation(
        initialCommand: ProcessInvocation,
        loginShellPath: String
    ) -> ProcessInvocation {
        return ProcessInvocation(
            executable: wrapperExecutable,
            arguments: [
                "-c",
                wrapperScript,
                "shade-command-sequence",
                loginShellPath,
                initialCommand.executable,
            ] + initialCommand.arguments
        )
    }

    /// SwiftTerm's nil environment is intentionally minimal for login shells,
    /// but a directly launched SSH client must inherit PATH, SSH_AUTH_SOCK and
    /// the rest of the app environment. Integration keys are overlaid for the
    /// wrapper and hidden from SSH by `wrapperScript` until the local shell starts.
    static func environment(
        inheritedEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        shellIntegrationEnvironment: [String]?,
        homeDirectory: String = NSHomeDirectory()
    ) -> [String] {
        var environment = inheritedEnvironment
        // An app started directly from an enriched Shade shell inherits these
        // exported implementation details. Drop them before applying the current
        // preference so disabling enrichment cannot leak stale state into SSH or
        // the fallback shell. ZDOTDIR itself is user environment and is preserved.
        for key in integrationKeys where key.hasPrefix("SHADE_") {
            environment.removeValue(forKey: key)
        }
        environment.removeValue(forKey: integrationMarker)
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        if environment["LANG"] == nil {
            environment["LANG"] = "en_US.UTF-8"
        }
        if environment["HOME"] == nil {
            environment["HOME"] = homeDirectory
        }
        if environment["PATH"]?.isEmpty != false {
            environment["PATH"] = defaultExecutablePath
        }

        if let shellIntegrationEnvironment {
            for entry in shellIntegrationEnvironment {
                let parts = entry.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2 else { continue }
                let key = String(parts[0])
                guard integrationKeys.contains(key) else { continue }
                environment[key] = String(parts[1])
            }
            environment[integrationMarker] = "1"
        }

        return environment.map { "\($0.key)=\($0.value)" }.sorted()
    }
}
