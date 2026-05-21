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

    // MARK: - branch() and findGitDir() against a fixture repo

    func testBranchFromDotGitHeadRefLine() throws {
        let dir = try makeFixtureRepo(headContents: "ref: refs/heads/main\n")
        defer { try? FileManager.default.removeItem(atPath: dir) }
        XCTAssertEqual(GitInfo.branch(forCwd: dir), "main")
    }

    func testBranchFromDetachedHeadSha() throws {
        let sha = "0123456789abcdef0123456789abcdef01234567"
        let dir = try makeFixtureRepo(headContents: "\(sha)\n")
        defer { try? FileManager.default.removeItem(atPath: dir) }
        XCTAssertEqual(GitInfo.branch(forCwd: dir), "0123456")
    }

    func testBranchInNestedSubdirectoryWalksUp() throws {
        let dir = try makeFixtureRepo(headContents: "ref: refs/heads/feature/x\n")
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let deep = (dir as NSString).appendingPathComponent("a/b/c")
        try FileManager.default.createDirectory(atPath: deep, withIntermediateDirectories: true)
        XCTAssertEqual(GitInfo.branch(forCwd: deep), "feature/x")
    }

    func testBranchNilWhenNoRepo() throws {
        let dir = NSTemporaryDirectory() + "shade-tests-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        XCTAssertNil(GitInfo.branch(forCwd: dir))
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
        XCTAssertEqual(GitInfo.branch(forCwd: work), "dev")
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

        XCTAssertEqual(GitInfo.branch(forCwd: work), "submodule-branch")
    }

    // MARK: - helpers

    private func makeFixtureRepo(headContents: String) throws -> String {
        let dir = NSTemporaryDirectory() + "shade-tests-" + UUID().uuidString
        let gitDir = (dir as NSString).appendingPathComponent(".git")
        try FileManager.default.createDirectory(atPath: gitDir, withIntermediateDirectories: true)
        try headContents.write(toFile: gitDir + "/HEAD", atomically: true, encoding: .utf8)
        return dir
    }
}
