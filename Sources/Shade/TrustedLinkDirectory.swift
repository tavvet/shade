import Darwin

/// A fail-closed source for implicit file links, separate from OSC 7/UI context.
/// Only a foreground system shell is recognized. Custom shells, multiplexers,
/// foreground commands and incompletely inspected trees get no fallback.
/// Process inspection is not atomic: rechecking reduces, but cannot eliminate,
/// races with exec, job creation, or chdir after the final check.
enum TrustedLinkDirectory {
    struct State: Equatable {
        var running: Bool
        var pid: pid_t
        var foregroundGroup: pid_t?
    }

    struct ShellIdentity: Equatable {
        var path: String
        var group: pid_t
        var startedSeconds: UInt64
        var startedMicroseconds: UInt64
        var backgroundProcesses: [String] = []
    }

    static func read(
        state: () -> State,
        inspect: (pid_t) -> ShellIdentity? = ProcessTree.idleLocalShell,
        cwd: (pid_t) -> String? = ProcessCwd.read
    ) -> String? {
        let before = state()
        guard before.running, before.pid > 0,
              before.foregroundGroup == before.pid,
              let identity = inspect(before.pid),
              identity.group == before.pid,
              let directory = cwd(before.pid), directory.hasPrefix("/"),
              !directory.utf8.contains(0),
              inspect(before.pid) == identity,
              state() == before else { return nil }
        return directory
    }
}
