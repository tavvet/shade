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

    /// Returns the basename of the remote-session process running somewhere in
    /// `shellPid`'s descendant tree, or nil if the shell is running locally.
    ///
    /// Walks *down* from the shell (which has only a handful of descendants)
    /// instead of scanning the whole system process table. That turns the cost
    /// from one `proc_pidpath` per process on the machine — every second, per
    /// tab — into a few syscalls over the shell's own subtree.
    static func remoteIndicator(forShell shellPid: pid_t) -> String? {
        guard shellPid > 0 else { return nil }

        var queue = children(of: shellPid)
        var visited = Set<pid_t>()
        // Bound the walk so a surprising tree (or pid reuse mid-scan) can't loop us.
        var budget = 1024
        while !queue.isEmpty, budget > 0 {
            budget -= 1
            let pid = queue.removeFirst()
            guard pid > 0, pid != shellPid, visited.insert(pid).inserted else { continue }
            if let name = processName(pid), remoteProcessNames.contains(name) {
                return name
            }
            queue.append(contentsOf: children(of: pid))
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
        var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let r = proc_pidpath(pid, &buf, UInt32(MAXPATHLEN))
        guard r > 0 else { return nil }
        // String(decoding:as:) — non-deprecated and available on macOS 13.
        // (String(validating:as:) is macOS 15+; String(cString:) is deprecated
        // on Swift 6 toolchains.)
        let bytes = buf.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
        let path = String(decoding: bytes, as: UTF8.self)
        guard !path.isEmpty else { return nil }
        return (path as NSString).lastPathComponent
    }
}
