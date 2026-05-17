import Darwin
import Foundation

/// Walks the process tree to spot when the shell has launched a remote-session
/// helper (ssh / mosh / etc). When that's the case, the local cwd/git heuristics
/// no longer reflect what the user sees in the terminal, so the UI should mask
/// them.
enum ProcessTree {
    /// Names that mean "the visible session is happening on another machine."
    static let remoteProcessNames: Set<String> = [
        "ssh", "mosh-client", "mosh", "tmate", "et", "eternalterminal",
    ]

    /// Returns the basename of the remote-session process that's a descendant of
    /// `shellPid`, or nil if the shell is running locally. Cheap enough to call
    /// once a second.
    static func remoteIndicator(forShell shellPid: pid_t) -> String? {
        guard shellPid > 0 else { return nil }

        // Snapshot every pid we own.
        let initialCount = proc_listallpids(nil, 0)
        guard initialCount > 0 else { return nil }
        let capacity = Int(initialCount) + 32   // small headroom for procs spawned mid-call
        var pids = [pid_t](repeating: 0, count: capacity)
        let written = proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.size))
        guard written > 0 else { return nil }

        for i in 0..<Int(written) {
            let pid = pids[i]
            guard pid > 0 else { continue }
            guard let name = processName(pid), remoteProcessNames.contains(name) else { continue }
            if hasAncestor(pid: pid, target: shellPid) {
                return name
            }
        }
        return nil
    }

    private static func processName(_ pid: pid_t) -> String? {
        var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let r = proc_pidpath(pid, &buf, UInt32(MAXPATHLEN))
        guard r > 0 else { return nil }
        let path = String(cString: buf)
        return (path as NSString).lastPathComponent
    }

    private static func hasAncestor(pid: pid_t, target: pid_t) -> Bool {
        var current = pid
        let infoSize = Int32(MemoryLayout<proc_bsdinfo>.stride)
        // Bounded walk so a cycle (shouldn't happen) can't lock us up.
        for _ in 0..<64 {
            var info = proc_bsdinfo()
            let r = proc_pidinfo(current, PROC_PIDTBSDINFO, 0, &info, infoSize)
            guard r == infoSize else { return false }
            let ppid = pid_t(info.pbi_ppid)
            if ppid == target { return true }
            if ppid <= 1 { return false }
            if ppid == current { return false }    // paranoia
            current = ppid
        }
        return false
    }
}
