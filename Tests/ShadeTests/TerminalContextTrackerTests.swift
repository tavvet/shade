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
            readRemoteIndicator: { _ in reportedRemote },
            findGitDir: { _ in "/repo/.git" },
            readBranch: { _ in "main" }
        )

        XCTAssertFalse(tracker.refresh(shellPid: 42, isActive: true))
        scheduler.apply(GitStatus(filesChanged: 1, insertions: 2, deletions: 3))
        XCTAssertEqual(tracker.cwd, "/repo")
        XCTAssertEqual(tracker.branch, "main")
        XCTAssertNotNil(tracker.gitStatus)

        reportedRemote = "ssh"
        XCTAssertTrue(tracker.refresh(shellPid: 42, isActive: true))

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
        tracker.refresh(shellPid: 7, isActive: true)
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

    private func makeTracker(
        scheduler: RecordingGitRefresh,
        readProcessCwd: @escaping (Int32) -> String? = { _ in nil },
        readRemoteIndicator: @escaping (Int32) -> String? = { _ in nil },
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
