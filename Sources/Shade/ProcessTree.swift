import Darwin
import Foundation

/// Checks the PTY owner and its process tree for a remote-session helper
/// (ssh / mosh / etc). When that's the case, the local cwd/git heuristics no
/// longer reflect what the user sees in the terminal, so the UI should mask them.
/// Also names the program running in place of the shell, for the quit question.
enum ProcessTree {
    /// Unlike the UI heuristics below, absence of a remote name is not proof
    /// of locality. Require an identified foreground system shell and a fully
    /// inspected tree with no foreground children. A wrapper running ssh
    /// cannot qualify, but positively identified background jobs may remain.
    static func idleLocalShell(_ pid: pid_t) -> TrustedLinkDirectory.ShellIdentity? {
        idleLocalShell(pid, metadata: { pid in
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
                  info.pbi_pid == UInt32(pid), info.pbi_status != UInt32(SZOMB),
                  let path = processPath(pid) else { return nil }
            return .init(path: path, group: pid_t(info.pbi_pgid),
                         startedSeconds: info.pbi_start_tvsec,
                         startedMicroseconds: info.pbi_start_tvusec)
        }, children: inspectedChildren)
    }

    /// libproc maps an underlying syscall failure to zero bytes, so errno
    /// distinguishes an unreadable tree from a successful empty snapshot.
    static func inspectedChildren(_ pid: pid_t) -> [pid_t]? {
        inspectedChildren(pid, list: { pid, buffer, capacity in
            proc_listpids(UInt32(PROC_PPID_ONLY), UInt32(pid), buffer, capacity)
        })
    }

    static func inspectedChildren(
        _ pid: pid_t,
        list: (pid_t, UnsafeMutableRawPointer, Int32) -> Int32
    ) -> [pid_t]? {
        guard pid > 0 else { return nil }
        var pids = [pid_t](repeating: 0, count: 64)
        let capacity = Int32(pids.count * MemoryLayout<pid_t>.stride)
        let (bytes, error) = pids.withUnsafeMutableBytes { buffer in
            errno = 0
            let bytes = list(pid, buffer.baseAddress!, capacity)
            let error = errno
            return (bytes, error)
        }
        // A full buffer cannot establish a complete tree.
        guard bytes >= 0, !(bytes == 0 && error != 0), bytes < capacity,
              Int(bytes) % MemoryLayout<pid_t>.stride == 0 else { return nil }
        return Array(pids.prefix(Int(bytes) / MemoryLayout<pid_t>.stride))
    }

    static func idleLocalShell(
        _ pid: pid_t,
        metadata: (pid_t) -> TrustedLinkDirectory.ShellIdentity?,
        children: (pid_t) -> [pid_t]?
    ) -> TrustedLinkDirectory.ShellIdentity? {
        guard pid > 0, var info = metadata(pid), info.group == pid,
              ["/bin/sh", "/bin/bash", "/bin/zsh", "/bin/ksh", "/bin/csh", "/bin/tcsh"].contains(info.path),
              let descendants = children(pid) else { return nil }
        var queue = descendants
        var visited: Set<pid_t> = [pid]
        while let child = queue.popLast() {
            guard child > 0, visited.insert(child).inserted, visited.count <= 1024,
                  let childInfo = metadata(child), childInfo.group > 0,
                  childInfo.group != pid, !childInfo.path.isEmpty,
                  let grandchildren = children(child) else { return nil }
            info.backgroundProcesses.append("\(child):\(childInfo.group):\(childInfo.startedSeconds):\(childInfo.startedMicroseconds):\(childInfo.path)")
            queue.append(contentsOf: grandchildren)
        }
        info.backgroundProcesses.sort()
        return info
    }

    /// Names that mean "the visible session is happening on another machine."
    static let remoteProcessNames: Set<String> = [
        "ssh", "mosh-client", "mosh", "tmate", "et", "eternalterminal",
    ]

    /// Returns the basename of a remote-session process in the PTY's foreground
    /// process group, or nil if the visible command is local. Background jobs
    /// must not hide the shell's local cwd/git context.
    ///
    /// Checks the PTY owner first, then walks *down* through its handful of
    /// descendants instead of scanning the whole system process table. That
    /// turns the cost from one `proc_pidpath` per process on the machine — every
    /// second, per tab — into a few syscalls over the terminal's own subtree.
    static func remoteIndicator(
        forShell shellPid: pid_t,
        foregroundProcessGroup: pid_t?
    ) -> String? {
        remoteIndicator(
            forShell: shellPid,
            foregroundProcessGroup: foregroundProcessGroup,
            children: children(of:),
            processName: processName,
            processGroup: processGroup
        )
    }

    /// Dependency-injected core used by tests so process-tree races and PID
    /// permissions do not make foreground/background behavior flaky.
    static func remoteIndicator(
        forShell shellPid: pid_t,
        foregroundProcessGroup: pid_t?,
        children: (pid_t) -> [pid_t],
        processName: (pid_t) -> String?,
        processGroup: (pid_t) -> pid_t?
    ) -> String? {
        guard shellPid > 0,
              let foregroundProcessGroup,
              foregroundProcessGroup > 0 else { return nil }

        // A terminal can also exec a remote client as its PTY owner. In that
        // case it commonly owns the foreground process group whose id is its pid.
        let ownerIsForeground = shellPid == foregroundProcessGroup
            || processGroup(shellPid) == foregroundProcessGroup
        if ownerIsForeground,
           let name = processName(shellPid),
           remoteProcessNames.contains(name) {
            return name
        }

        var queue = children(shellPid)
        var visited = Set<pid_t>()
        // Bound the walk so a surprising tree (or pid reuse mid-scan) can't loop us.
        var budget = 1024
        while !queue.isEmpty, budget > 0 {
            budget -= 1
            let pid = queue.removeFirst()
            guard pid > 0, pid != shellPid, visited.insert(pid).inserted else { continue }
            if processGroup(pid) == foregroundProcessGroup,
               let name = processName(pid),
               remoteProcessNames.contains(name) {
                return name
            }
            queue.append(contentsOf: children(pid))
        }
        return nil
    }

    /// Name of the program the PTY runs in the foreground in place of its shell,
    /// or nil while the shell itself waits for input.
    static func foregroundProgram(
        forShell shellPid: pid_t,
        foregroundProcessGroup: pid_t?
    ) -> String? {
        foregroundProgram(
            forShell: shellPid,
            foregroundProcessGroup: foregroundProcessGroup,
            children: children(of:),
            processName: processName,
            processGroup: processGroup
        )
    }

    /// Dependency-injected core of `foregroundProgram(forShell:foregroundProcessGroup:)`.
    static func foregroundProgram(
        forShell shellPid: pid_t,
        foregroundProcessGroup: pid_t?,
        children: (pid_t) -> [pid_t],
        processName: (pid_t) -> String?,
        processGroup: (pid_t) -> pid_t?
    ) -> String? {
        guard shellPid > 0,
              let foregroundProcessGroup,
              foregroundProcessGroup > 0 else { return nil }

        let ownerIsForeground = shellPid == foregroundProcessGroup
            || processGroup(shellPid) == foregroundProcessGroup
        guard ownerIsForeground else {
            // An interactive shell gives each command its own process group,
            // led by the command's first process.
            return processName(foregroundProcessGroup) ?? "process \(foregroundProcessGroup)"
        }
        // The command-sequence wrapper (/bin/sh, no job control) runs its
        // command, such as ssh, as a child in the wrapper's own group.
        for child in children(shellPid) where child > 0 && processGroup(child) == foregroundProcessGroup {
            if let name = processName(child) { return name }
        }
        return nil
    }

    /// Immediate children of `pid` via libproc. Returns [] when there are none.
    private static func children(of pid: pid_t) -> [pid_t] {
        var capacity = 64
        while true {
            var pids = [pid_t](repeating: 0, count: capacity)
            let n = proc_listchildpids(pid, &pids, Int32(capacity * MemoryLayout<pid_t>.size))
            guard n > 0 else { return [] }
            let count = Int(n)
            // A full buffer means the list may have been truncated — grow and retry.
            if count < capacity { return Array(pids.prefix(count)) }
            capacity *= 2
            if capacity > 4096 { return Array(pids.prefix(count)) }
        }
    }

    private static func processName(_ pid: pid_t) -> String? {
        processPath(pid).map { ($0 as NSString).lastPathComponent }
    }

    private static func processPath(_ pid: pid_t) -> String? {
        var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let r = proc_pidpath(pid, &buf, UInt32(MAXPATHLEN))
        guard r > 0 else { return nil }
        // String(decoding:as:) — non-deprecated and available on macOS 13.
        // (String(validating:as:) is macOS 15+; String(cString:) is deprecated
        // on Swift 6 toolchains.)
        let bytes = buf.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
        let path = String(decoding: bytes, as: UTF8.self)
        guard !path.isEmpty else { return nil }
        return path
    }

    private static func processGroup(_ pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
        let written = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
        guard written == size else { return nil }
        return pid_t(info.pbi_pgid)
    }
}
