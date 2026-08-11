import Foundation

/// Locates Git repository metadata and reads the current branch without
/// spawning a subprocess. Keeping these filesystem-only operations together
/// lets status refreshes reuse a known `.git` directory.
enum GitRepository {
    /// Returns the branch name, or a 7-character SHA prefix for detached HEAD,
    /// or nil when the working directory is not inside a Git repository.
    static func branch(forCwd cwd: String) -> String? {
        guard let gitDir = findGitDir(from: cwd) else { return nil }
        return branchName(inGitDir: gitDir)
    }

    /// Reads the current branch from `<gitDir>/HEAD` for callers that already
    /// know the repository metadata directory.
    static func branchName(inGitDir gitDir: String) -> String? {
        let head = (gitDir as NSString).appendingPathComponent("HEAD")
        guard let content = try? String(contentsOfFile: head, encoding: .utf8) else { return nil }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let refPrefix = "ref: refs/heads/"
        if trimmed.hasPrefix(refPrefix) {
            return String(trimmed.dropFirst(refPrefix.count))
        }
        if trimmed.count >= 7, trimmed.allSatisfy({ $0.isHexDigit }) {
            return String(trimmed.prefix(7))
        }
        return nil
    }

    /// Walks up from `path` looking for a `.git` directory or worktree pointer
    /// file and returns the resolved metadata directory.
    static func findGitDir(from path: String) -> String? {
        let fileManager = FileManager.default
        var current = (path as NSString).standardizingPath
        while !current.isEmpty, current != "/" {
            let candidate = (current as NSString).appendingPathComponent(".git")
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: candidate, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    return candidate
                }
                if let resolved = resolveGitDirPointer(at: candidate, relativeTo: current) {
                    return resolved
                }
            }
            current = (current as NSString).deletingLastPathComponent
        }
        return nil
    }

    private static func resolveGitDirPointer(at path: String, relativeTo directory: String) -> String? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let line = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "gitdir: "
        guard line.hasPrefix(prefix) else { return nil }

        let rawGitDir = String(line.dropFirst(prefix.count))
        if rawGitDir.hasPrefix("/") {
            return (rawGitDir as NSString).standardizingPath
        }
        return ((directory as NSString).appendingPathComponent(rawGitDir) as NSString)
            .standardizingPath
    }
}
