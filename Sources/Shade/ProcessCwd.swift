import Darwin

/// Reads a process's current working directory via libproc.
/// Works for any process the user owns; no shell cooperation required.
enum ProcessCwd {
    static func read(pid: pid_t) -> String? {
        guard pid > 0 else { return nil }
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.stride)
        let written = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size)
        guard written == size else { return nil }
        return withUnsafePointer(to: &info.pvi_cdir.vip_path) { tuplePtr in
            tuplePtr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                String(cString: $0)
            }
        }
    }
}
