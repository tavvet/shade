import XCTest
@testable import Shade

final class GitInfoTests: XCTestCase {
    // MARK: - firstNumber parsing (shortstat-style strings)

    func testFirstNumberInsertions() {
        let text = " 3 files changed, 42 insertions(+), 5 deletions(-)"
        XCTAssertEqual(GitInfo.firstNumber(in: text, before: "insertion"), 42)
        XCTAssertEqual(GitInfo.firstNumber(in: text, before: "deletion"), 5)
    }

    func testFirstNumberOnlyInsertions() {
        let text = " 1 file changed, 7 insertions(+)"
        XCTAssertEqual(GitInfo.firstNumber(in: text, before: "insertion"), 7)
        XCTAssertNil(GitInfo.firstNumber(in: text, before: "deletion"))
    }

    func testFirstNumberAbsentReturnsNil() {
        XCTAssertNil(GitInfo.firstNumber(in: "", before: "insertion"))
        XCTAssertNil(GitInfo.firstNumber(in: "no numbers here", before: "insertion"))
    }

    // MARK: - repository metadata against a fixture repo

    func testBranchFromDotGitHeadRefLine() throws {
        let dir = try makeFixtureRepo(headContents: "ref: refs/heads/main\n")
        defer { try? FileManager.default.removeItem(atPath: dir) }
        XCTAssertEqual(GitRepository.branch(forCwd: dir), "main")
    }

    func testBranchFromDetachedHeadSha() throws {
        let sha = "0123456789abcdef0123456789abcdef01234567"
        let dir = try makeFixtureRepo(headContents: "\(sha)\n")
        defer { try? FileManager.default.removeItem(atPath: dir) }
        XCTAssertEqual(GitRepository.branch(forCwd: dir), "0123456")
    }

    func testBranchInNestedSubdirectoryWalksUp() throws {
        let dir = try makeFixtureRepo(headContents: "ref: refs/heads/feature/x\n")
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let deep = (dir as NSString).appendingPathComponent("a/b/c")
        try FileManager.default.createDirectory(atPath: deep, withIntermediateDirectories: true)
        XCTAssertEqual(
            GitRepository.findGitDir(from: deep),
            (dir as NSString).appendingPathComponent(".git")
        )
        XCTAssertEqual(GitRepository.branch(forCwd: deep), "feature/x")
    }

    func testBranchNilWhenNoRepo() throws {
        let dir = NSTemporaryDirectory() + "shade-tests-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        XCTAssertNil(GitRepository.branch(forCwd: dir))
    }

    func testStatusDistinguishesMissingRepository() async throws {
        let dir = NSTemporaryDirectory() + "shade-tests-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let result = await GitInfo.statusCancellable(forCwd: dir)

        XCTAssertEqual(result, .notRepository)
    }

    func testStatusReportsFailureInsteadOfCleanWhenGitCommandFails() async throws {
        // The HEAD-only fixture passes Shade's cheap repository discovery but
        // is intentionally incomplete, so the real `git status` command fails.
        let dir = try makeFixtureRepo(headContents: "ref: refs/heads/main\n")
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let result = await GitInfo.statusCancellable(forCwd: dir)

        XCTAssertEqual(result, .failed)
    }

    func testStatusKeepsFileCountWhenRepositoryHasNoHead() async throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try runGit(["init", "--quiet"], in: dir)
        try "draft\n".write(toFile: dir + "/draft.txt", atomically: true, encoding: .utf8)

        let result = await GitInfo.statusCancellable(forCwd: dir)

        XCTAssertEqual(
            result,
            .status(GitStatus(filesChanged: 1, insertions: 0, deletions: 0))
        )
    }

    func testStatusReportsFailureWhenShortstatFailsWithExistingHead() async throws {
        let dir = try makeFixtureRepo(headContents: "ref: refs/heads/main\n")
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let runner = GitCommandRunnerStub(outputs: [
            " M tracked.txt\n",
            nil,
            "0123456789abcdef\n",
        ])

        let result = await GitInfo.statusCancellable(
            forCwd: dir,
            runGit: { arguments in await runner.run(arguments) }
        )

        XCTAssertEqual(result, .failed)
        let commands = await runner.commands
        XCTAssertEqual(commands.map { Array($0.dropFirst(2)) }, [
            ["status", "--porcelain"],
            ["diff", "--shortstat", "HEAD"],
            ["rev-parse", "--verify", "HEAD"],
        ])
    }

    func testFindGitDirHandlesWorktreePointerFile() throws {
        // A worktree's `.git` is a *file* with `gitdir: <abs path>` inside.
        let real = NSTemporaryDirectory() + "shade-tests-real-" + UUID().uuidString
        let work = NSTemporaryDirectory() + "shade-tests-work-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: real, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: work, withIntermediateDirectories: true)
        try "ref: refs/heads/dev\n".write(toFile: real + "/HEAD", atomically: true, encoding: .utf8)
        try "gitdir: \(real)\n".write(toFile: work + "/.git", atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(atPath: real)
            try? FileManager.default.removeItem(atPath: work)
        }
        XCTAssertEqual(GitRepository.findGitDir(from: work), real)
        XCTAssertEqual(GitRepository.branch(forCwd: work), "dev")
    }

    func testFindGitDirResolvesRelativePointerFile() throws {
        // Submodules commonly store a relative `gitdir:` pointer.
        let root = NSTemporaryDirectory() + "shade-tests-" + UUID().uuidString
        let real = (root as NSString).appendingPathComponent("real-git")
        let work = (root as NSString).appendingPathComponent("work")
        try FileManager.default.createDirectory(atPath: real, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: work, withIntermediateDirectories: true)
        try "ref: refs/heads/submodule-branch\n".write(toFile: real + "/HEAD", atomically: true, encoding: .utf8)
        try "gitdir: ../real-git\n".write(toFile: work + "/.git", atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: root) }

        XCTAssertEqual(GitRepository.findGitDir(from: work), real)
        XCTAssertEqual(GitRepository.branch(forCwd: work), "submodule-branch")
    }

    // MARK: - repository branch reads HEAD directly

    func testBranchNameReadsHeadInGivenGitDir() throws {
        let dir = try makeFixtureRepo(headContents: "ref: refs/heads/topic\n")
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let gitDir = (dir as NSString).appendingPathComponent(".git")
        XCTAssertEqual(GitRepository.branchName(inGitDir: gitDir), "topic")
    }

    func testBranchNameNilWhenHeadMissing() {
        let missing = NSTemporaryDirectory() + "shade-tests-missing-" + UUID().uuidString
        XCTAssertNil(GitRepository.branchName(inGitDir: missing))
    }

    // MARK: - helpers

    private func makeFixtureRepo(headContents: String) throws -> String {
        let dir = NSTemporaryDirectory() + "shade-tests-" + UUID().uuidString
        let gitDir = (dir as NSString).appendingPathComponent(".git")
        try FileManager.default.createDirectory(atPath: gitDir, withIntermediateDirectories: true)
        try headContents.write(toFile: gitDir + "/HEAD", atomically: true, encoding: .utf8)
        return dir
    }

    private func makeTemporaryDirectory() throws -> String {
        let dir = NSTemporaryDirectory() + "shade-tests-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    private func runGit(_ arguments: [String], in directory: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", directory] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw GitFixtureError.commandFailed(arguments, process.terminationStatus)
        }
    }
}

private enum GitFixtureError: Error {
    case commandFailed([String], Int32)
}

private actor GitCommandRunnerStub {
    private var outputs: [String?]
    private(set) var commands: [[String]] = []

    init(outputs: [String?]) {
        self.outputs = outputs
    }

    func run(_ arguments: [String]) -> String? {
        commands.append(arguments)
        return outputs.removeFirst()
    }
}
