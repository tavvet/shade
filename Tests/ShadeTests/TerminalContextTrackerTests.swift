import XCTest
@testable import Shade

@MainActor
final class TerminalContextTrackerTests: XCTestCase {
    func testCwdChangeResolvesRepositoryAndSchedulesStatusOnce() {
        let scheduler = RecordingGitRefresh()
        var resolvedPaths: [String] = []
        let tracker = makeTracker(
            scheduler: scheduler,
            findGitDir: { path in
                resolvedPaths.append(path)
                return "/repo/.git"
            }
        )
        var changes: [TerminalContextTracker.Change] = []
        tracker.onChange = { changes.append($0) }

        tracker.updateCwd("/repo/subdir")
        tracker.updateCwd("/repo/subdir")

        XCTAssertEqual(tracker.cwd, "/repo/subdir")
        XCTAssertEqual(resolvedPaths, ["/repo/subdir"])
        XCTAssertEqual(scheduler.calls, [
            .init(path: "/repo/subdir", reason: .cwdChanged),
        ])
        XCTAssertEqual(changes, [.cwd])
    }

    func testRemoteSessionMasksLocalContextAndCancelsStatus() {
        let scheduler = RecordingGitRefresh()
        var reportedRemote: String?
        let tracker = makeTracker(
            scheduler: scheduler,
            readProcessCwd: { _ in "/repo" },
            readRemoteIndicator: { _, _ in reportedRemote },
            findGitDir: { _ in "/repo/.git" },
            readBranch: { _ in "main" }
        )

        XCTAssertFalse(tracker.refresh(shellPid: 42, foregroundProcessGroup: 42, isActive: true))
        scheduler.apply(GitStatus(filesChanged: 1, insertions: 2, deletions: 3))
        XCTAssertEqual(tracker.cwd, "/repo")
        XCTAssertEqual(tracker.branch, "main")
        XCTAssertNotNil(tracker.gitStatus)

        reportedRemote = "ssh"
        XCTAssertTrue(tracker.refresh(shellPid: 42, foregroundProcessGroup: 84, isActive: true))

        XCTAssertEqual(tracker.remoteIndicator, "ssh")
        XCTAssertEqual(tracker.cwd, "")
        XCTAssertEqual(tracker.branch, "")
        XCTAssertNil(tracker.gitStatus)
        XCTAssertEqual(scheduler.cancelCount, 1)
    }

    func testCommandFinishedReplacesFallbackWithStrongRefresh() {
        let scheduler = RecordingGitRefresh()
        let tracker = makeTracker(
            scheduler: scheduler,
            readProcessCwd: { _ in "/repo" },
            findGitDir: { _ in "/repo/.git" },
            readBranch: { _ in "main" }
        )
        tracker.refresh(shellPid: 7, foregroundProcessGroup: 7, isActive: true)
        scheduler.calls.removeAll()

        tracker.fallbackRefreshGitStatusIfNeeded()
        XCTAssertEqual(scheduler.calls, [.init(path: "/repo", reason: .fallbackPoll)])
        scheduler.calls.removeAll()

        tracker.commandFinished(shellPid: 7)
        XCTAssertEqual(scheduler.calls, [.init(path: "/repo", reason: .commandFinished)])
        scheduler.calls.removeAll()

        tracker.fallbackRefreshGitStatusIfNeeded()
        XCTAssertTrue(scheduler.calls.isEmpty)
    }

    func testCommandFinishDiscoversNewRepositoryWithoutCwdChange() throws {
        let fixture = try RepositoryDiscoveryFixture()
        defer { fixture.remove() }
        let scheduler = RecordingGitRefresh()
        let tracker = makeRepositoryTracker(scheduler: scheduler, cwd: fixture.directory)
        tracker.refresh(shellPid: 7, foregroundProcessGroup: 7, isActive: true)
        XCTAssertTrue(tracker.branch.isEmpty)
        scheduler.calls.removeAll()

        try fixture.addRepository(at: fixture.directory, branch: "new-main")
        tracker.commandFinished(shellPid: 7)

        XCTAssertEqual(tracker.cwd, fixture.directory.path)
        XCTAssertEqual(tracker.branch, "new-main")
        XCTAssertEqual(scheduler.calls, [
            .init(path: fixture.directory.path, reason: .commandFinished),
        ])
    }

    func testPollDiscoversNewRepositoryWithoutShellIntegrationOrCwdChange() throws {
        let fixture = try RepositoryDiscoveryFixture()
        defer { fixture.remove() }
        let scheduler = RecordingGitRefresh()
        let tracker = makeRepositoryTracker(scheduler: scheduler, cwd: fixture.directory)
        tracker.refresh(shellPid: 7, foregroundProcessGroup: 7, isActive: true)
        scheduler.calls.removeAll()

        try fixture.addRepository(at: fixture.directory, branch: "new-main")
        tracker.refresh(shellPid: 7, foregroundProcessGroup: 7, isActive: true)
        tracker.fallbackRefreshGitStatusIfNeeded()

        XCTAssertEqual(tracker.cwd, fixture.directory.path)
        XCTAssertEqual(tracker.branch, "new-main")
        XCTAssertEqual(scheduler.calls, [
            .init(path: fixture.directory.path, reason: .cwdChanged),
            .init(path: fixture.directory.path, reason: .fallbackPoll),
        ])
    }

    func testNestedRepositoryReplacesParentWithAndWithoutShellIntegration() throws {
        for usesShellIntegration in [true, false] {
            let fixture = try RepositoryDiscoveryFixture()
            defer { fixture.remove() }
            let nested = fixture.directory.appendingPathComponent("nested")
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            try fixture.addRepository(at: fixture.directory, branch: "parent-main")
            let scheduler = RecordingGitRefresh()
            let tracker = makeRepositoryTracker(scheduler: scheduler, cwd: nested)
            tracker.refresh(shellPid: 7, foregroundProcessGroup: 7, isActive: true)
            scheduler.apply(GitStatus(filesChanged: 9, insertions: 8, deletions: 7))
            XCTAssertEqual(tracker.branch, "parent-main")
            scheduler.calls.removeAll()

            try fixture.addRepository(at: nested, branch: "nested-main")
            if usesShellIntegration {
                tracker.commandFinished(shellPid: 7)
            } else {
                tracker.refresh(shellPid: 7, foregroundProcessGroup: 7, isActive: true)
            }

            XCTAssertEqual(tracker.cwd, nested.path)
            XCTAssertEqual(tracker.branch, "nested-main")
            XCTAssertNil(tracker.gitStatus, "Parent status must not be displayed for the nested repository")
            XCTAssertEqual(scheduler.calls, [
                .init(path: nested.path, reason: usesShellIntegration ? .commandFinished : .cwdChanged),
            ])
        }
    }

    func testRemovingRepositoryClearsBranchAndStatusWithoutCwdChange() throws {
        let fixture = try RepositoryDiscoveryFixture()
        defer { fixture.remove() }
        try fixture.addRepository(at: fixture.directory, branch: "main")
        let scheduler = RecordingGitRefresh()
        let tracker = makeRepositoryTracker(scheduler: scheduler, cwd: fixture.directory)
        tracker.refresh(shellPid: 7, foregroundProcessGroup: 7, isActive: true)
        scheduler.apply(GitStatus(filesChanged: 2, insertions: 3, deletions: 4))
        scheduler.calls.removeAll()

        try FileManager.default.removeItem(at: fixture.directory.appendingPathComponent(".git"))
        tracker.refresh(shellPid: 7, foregroundProcessGroup: 7, isActive: true)

        XCTAssertTrue(tracker.branch.isEmpty)
        XCTAssertNil(tracker.gitStatus)
        XCTAssertEqual(scheduler.calls, [
            .init(path: fixture.directory.path, reason: .cwdChanged),
        ])
    }

    private func makeRepositoryTracker(
        scheduler: RecordingGitRefresh,
        cwd: URL
    ) -> TerminalContextTracker {
        makeTracker(
            scheduler: scheduler,
            readProcessCwd: { _ in cwd.path },
            findGitDir: { GitRepository.findGitDir(from: $0) },
            readBranch: { GitRepository.branchName(inGitDir: $0) }
        )
    }

    private func makeTracker(
        scheduler: RecordingGitRefresh,
        readProcessCwd: @escaping (Int32) -> String? = { _ in nil },
        readRemoteIndicator: @escaping (Int32, Int32?) -> String? = { _, _ in nil },
        findGitDir: @escaping (String) -> String? = { _ in nil },
        readBranch: @escaping (String) -> String? = { _ in nil }
    ) -> TerminalContextTracker {
        TerminalContextTracker(
            readProcessCwd: readProcessCwd,
            readRemoteIndicator: readRemoteIndicator,
            findGitDir: findGitDir,
            readBranch: readBranch,
            gitRefreshFactory: { apply in
                scheduler.apply = apply
                return scheduler
            }
        )
    }
}

/// The metadata read by repository discovery after `git init`; no subprocess
/// or user's Git configuration is needed to exercise same-directory changes.
private struct RepositoryDiscoveryFixture {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("shade-repository-discovery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func addRepository(at directory: URL, branch: String) throws {
        let metadata = directory.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        try "ref: refs/heads/\(branch)\n".write(
            to: metadata.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private final class RecordingGitRefresh: GitRefreshScheduling {
    struct Call: Equatable {
        let path: String
        let reason: GitRefreshCoordinator.Reason
    }

    var calls: [Call] = []
    var cancelCount = 0
    var apply: GitRefreshCoordinator.Apply = { _ in }

    func schedule(path: String, reason: GitRefreshCoordinator.Reason) {
        calls.append(Call(path: path, reason: reason))
    }

    func cancel() {
        cancelCount += 1
    }
}
