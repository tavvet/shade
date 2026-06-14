import Foundation

struct GitStatus: Equatable {
    var filesChanged: Int
    var insertions: Int
    var deletions: Int

    static let empty = GitStatus(filesChanged: 0, insertions: 0, deletions: 0)
    var isClean: Bool { filesChanged == 0 && insertions == 0 && deletions == 0 }
}

/// Git introspection helpers for a working directory.
/// Branch is read directly from `.git/HEAD` (no subprocess, fast). Working-tree status
/// uses the real `git` binary because reproducing porcelain output ourselves would mean
/// re-implementing index/diff logic.
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

    /// Async variant used by the UI refresh coordinator. Cancellation terminates
    /// any in-flight `git` subprocess so rapid tab/cwd changes do not pile up work.
    static func statusCancellable(forCwd cwd: String) async -> GitStatus? {
        guard findGitDir(from: cwd) != nil else { return nil }
        let porcelain = await runGitCancellable(["-C", cwd, "status", "--porcelain"]) ?? ""
        guard !Task.isCancelled else { return nil }
        let filesChanged = porcelain
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .filter { !$0.isEmpty }
            .count

        let shortstat = await runGitCancellable(["-C", cwd, "diff", "--shortstat", "HEAD"]) ?? ""
        guard !Task.isCancelled else { return nil }
        let insertions = firstNumber(in: shortstat, before: "insertion") ?? 0
        let deletions = firstNumber(in: shortstat, before: "deletion") ?? 0

        return GitStatus(filesChanged: filesChanged, insertions: insertions, deletions: deletions)
    }

    private static func runGitCancellable(_ args: [String]) async -> String? {
        let runner = CancellableGitProcess(args: args)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                runner.run { output in
                    continuation.resume(returning: output)
                }
            }
        } onCancel: {
            runner.cancel()
        }
    }

    /// Pulls the integer that immediately precedes `keyword` in a shortstat-like line.
    static func firstNumber(in text: String, before keyword: String) -> Int? {
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
    static func findGitDir(from path: String) -> String? {
        let fm = FileManager.default
        var current = (path as NSString).standardizingPath
        while !current.isEmpty, current != "/" {
            let candidate = (current as NSString).appendingPathComponent(".git")
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: candidate, isDirectory: &isDir) {
                if isDir.boolValue {
                    return candidate
                }
                // Worktree/submodule: `.git` can be a pointer file. Relative
                // gitdir paths are resolved from the directory containing `.git`.
                if let content = try? String(contentsOfFile: candidate, encoding: .utf8) {
                    let line = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    let gitDirPrefix = "gitdir: "
                    if line.hasPrefix(gitDirPrefix) {
                        let rawGitDir = String(line.dropFirst(gitDirPrefix.count))
                        if rawGitDir.hasPrefix("/") {
                            return (rawGitDir as NSString).standardizingPath
                        }
                        return ((current as NSString).appendingPathComponent(rawGitDir) as NSString)
                            .standardizingPath
                    }
                }
            }
            current = (current as NSString).deletingLastPathComponent
        }
        return nil
    }
}

private final class CancellableGitProcess: @unchecked Sendable {
    private let args: [String]
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    init(args: [String]) {
        self.args = args
    }

    func run(completion: @escaping @Sendable (String?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            proc.arguments = ["git"] + self.args
            let out = Pipe()
            proc.standardOutput = out
            // stderr is never read; route it to /dev/null so a chatty git (e.g. autocrlf
            // warnings on a big dirty tree) can't fill the pipe buffer and wedge the process.
            proc.standardError = FileHandle.nullDevice

            self.lock.lock()
            let shouldStart = !self.cancelled
            self.lock.unlock()
            guard shouldStart else {
                completion(nil)
                return
            }

            do {
                try proc.run()
            } catch {
                completion(nil)
                return
            }

            self.lock.lock()
            if self.cancelled {
                self.lock.unlock()
                proc.terminate()
            } else {
                self.process = proc
                self.lock.unlock()
            }

            let data = out.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()

            self.lock.lock()
            self.process = nil
            self.lock.unlock()

            guard proc.terminationStatus == 0 else {
                completion(nil)
                return
            }
            completion(String(data: data, encoding: .utf8))
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let proc = process
        lock.unlock()

        if proc?.isRunning == true {
            proc?.terminate()
        }
    }
}
