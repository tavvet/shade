import Foundation

struct GitStatus: Equatable, Sendable {
    var filesChanged: Int
    var insertions: Int
    var deletions: Int

    static let empty = GitStatus(filesChanged: 0, insertions: 0, deletions: 0)
    var isClean: Bool { filesChanged == 0 && insertions == 0 && deletions == 0 }
}

/// Distinguishes an authoritative Git result from a transient command failure.
/// A failed refresh must not make the UI replace its last good status with a
/// clean or missing state.
enum GitStatusRefreshResult: Equatable, Sendable {
    case status(GitStatus)
    case notRepository
    case failed
}

/// Builds a working-tree status from Git porcelain output. Repository discovery
/// and process execution live in dedicated collaborators.
enum GitInfo {
    typealias CommandRunner = @Sendable ([String]) async -> String?

    /// Async variant used by the UI refresh coordinator. Cancellation terminates
    /// any in-flight `git` subprocess so rapid tab/cwd changes do not pile up work.
    static func statusCancellable(forCwd cwd: String) async -> GitStatusRefreshResult {
        await statusCancellable(forCwd: cwd, runGit: GitProcessRunner.run)
    }

    /// Runner-injected variant keeps command-failure classification directly
    /// testable without depending on mutable global Git configuration.
    static func statusCancellable(
        forCwd cwd: String,
        runGit: CommandRunner
    ) async -> GitStatusRefreshResult {
        guard GitRepository.findGitDir(from: cwd) != nil else { return .notRepository }
        guard let porcelain = await runGit(["-C", cwd, "status", "--porcelain"])
        else { return .failed }
        guard !Task.isCancelled else { return .failed }
        let filesChanged = porcelain
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .filter { !$0.isEmpty }
            .count

        let shortstat: String
        if let output = await runGit(["-C", cwd, "diff", "--shortstat", "HEAD"]) {
            shortstat = output
        } else {
            guard !Task.isCancelled else { return .failed }
            guard GitRepository.findGitDir(from: cwd) != nil else { return .notRepository }

            // `git diff HEAD` legitimately fails before the first commit. Only
            // that case may degrade line counts to zero; if HEAD resolves, the
            // diff command itself failed and the last good snapshot must win.
            let head = await runGit(["-C", cwd, "rev-parse", "--verify", "HEAD"])
            guard !Task.isCancelled else { return .failed }
            guard head == nil else { return .failed }
            shortstat = ""
        }
        let insertions = firstNumber(in: shortstat, before: "insertion") ?? 0
        let deletions = firstNumber(in: shortstat, before: "deletion") ?? 0

        return .status(
            GitStatus(filesChanged: filesChanged, insertions: insertions, deletions: deletions)
        )
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

}
