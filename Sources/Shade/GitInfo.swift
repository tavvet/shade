import Foundation

struct GitStatus: Equatable {
    var filesChanged: Int
    var insertions: Int
    var deletions: Int

    static let empty = GitStatus(filesChanged: 0, insertions: 0, deletions: 0)
    var isClean: Bool { filesChanged == 0 && insertions == 0 && deletions == 0 }
}

/// Best-effort git branch lookup for a given working directory.
/// Branch is read directly from `.git/HEAD` (no subprocess); diff stats use `git`.
enum GitInfo {
    /// Returns the branch name, or a 7-char SHA prefix for detached HEAD, or nil if the
    /// directory is not inside a git repository.
    static func branch(forCwd cwd: String) -> String? {
        guard let gitDir = findGitDir(from: cwd) else { return nil }
        let head = (gitDir as NSString).appendingPathComponent("HEAD")
        guard let content = try? String(contentsOfFile: head, encoding: .utf8) else { return nil }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let refPrefix = "ref: refs/heads/"
        if trimmed.hasPrefix(refPrefix) {
            return String(trimmed.dropFirst(refPrefix.count))
        }
        // Detached HEAD: the file contains the raw commit SHA.
        if trimmed.count >= 7, trimmed.allSatisfy({ $0.isHexDigit }) {
            return String(trimmed.prefix(7))
        }
        return nil
    }

    /// Runs `git status --porcelain` and `git diff --shortstat HEAD` to summarize working-tree
    /// changes. Returns nil if not in a repo, .empty if the tree is clean.
    static func status(forCwd cwd: String) -> GitStatus? {
        guard findGitDir(from: cwd) != nil else { return nil }
        let porcelain = runGit(["-C", cwd, "status", "--porcelain"]) ?? ""
        let filesChanged = porcelain
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .filter { !$0.isEmpty }
            .count

        let shortstat = runGit(["-C", cwd, "diff", "--shortstat", "HEAD"]) ?? ""
        let insertions = firstNumber(in: shortstat, before: "insertion") ?? 0
        let deletions = firstNumber(in: shortstat, before: "deletion") ?? 0

        return GitStatus(filesChanged: filesChanged, insertions: insertions, deletions: deletions)
    }

    private static func runGit(_ args: [String]) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["git"] + args
        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return nil
        }
        guard proc.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    /// Pulls the integer that immediately precedes `keyword` in a shortstat-like line.
    private static func firstNumber(in text: String, before keyword: String) -> Int? {
        guard let kwRange = text.range(of: keyword) else { return nil }
        let prefix = text[..<kwRange.lowerBound]
        var digits = ""
        for ch in prefix.reversed() {
            if ch.isNumber { digits.insert(ch, at: digits.startIndex) }
            else if !digits.isEmpty { break }
        }
        return Int(digits)
    }

    /// Walks up from `path` looking for a `.git` directory (or a worktree pointer file).
    /// Returns the resolved git directory path, or nil.
    private static func findGitDir(from path: String) -> String? {
        let fm = FileManager.default
        var current = (path as NSString).standardizingPath
        while !current.isEmpty, current != "/" {
            let candidate = (current as NSString).appendingPathComponent(".git")
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: candidate, isDirectory: &isDir) {
                if isDir.boolValue {
                    return candidate
                }
                // Worktree: `.git` is a file whose content is `gitdir: <absolute path>`.
                if let content = try? String(contentsOfFile: candidate, encoding: .utf8) {
                    let line = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    let gitDirPrefix = "gitdir: "
                    if line.hasPrefix(gitDirPrefix) {
                        return String(line.dropFirst(gitDirPrefix.count))
                    }
                }
            }
            current = (current as NSString).deletingLastPathComponent
        }
        return nil
    }
}

private extension Character {
    var isHexDigit: Bool {
        ("0"..."9").contains(self) || ("a"..."f").contains(self) || ("A"..."F").contains(self)
    }
}
