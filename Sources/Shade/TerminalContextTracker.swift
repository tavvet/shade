import Foundation

/// Minimal scheduling surface used by terminal context tracking. Keeping the
/// policy behind a protocol makes CWD/Git/remote state transitions testable
/// without spawning git subprocesses or waiting for debounce timers.
@MainActor
protocol GitRefreshScheduling: AnyObject {
    func schedule(path: String, reason: GitRefreshCoordinator.Reason)
    func cancel()
}

extension GitRefreshCoordinator: GitRefreshScheduling {}

/// Owns the local context inferred for one shell process: CWD, repository,
/// branch/status and remote-session masking. It deliberately knows nothing
/// about terminal UI, tab titles or notifications.
@MainActor
final class TerminalContextTracker {
    enum Change: Equatable {
        case cwd
        case branch
        case gitStatus
        case remoteIndicator
    }

    typealias GitRefreshFactory = (@escaping GitRefreshCoordinator.Apply) -> any GitRefreshScheduling

    var onChange: ((Change) -> Void)?

    private(set) var cwd = ""
    private(set) var branch = ""
    private(set) var gitStatus: GitStatus?
    private(set) var remoteIndicator: String?

    private var gitDir: String?
    private var sawCommandFinishedMark = false
    private let gitRefreshFactory: GitRefreshFactory
    private lazy var gitRefresh: any GitRefreshScheduling = gitRefreshFactory { [weak self] status in
        self?.setGitStatus(status)
    }

    private let readProcessCwd: (Int32) -> String?
    private let readRemoteIndicator: (Int32, Int32?) -> String?
    private let findGitDir: (String) -> String?
    private let readBranch: (String) -> String?

    init(
        readProcessCwd: @escaping (Int32) -> String? = { ProcessCwd.read(pid: $0) },
        readRemoteIndicator: @escaping (Int32, Int32?) -> String? = {
            ProcessTree.remoteIndicator(forShell: $0, foregroundProcessGroup: $1)
        },
        findGitDir: @escaping (String) -> String? = { GitInfo.findGitDir(from: $0) },
        readBranch: @escaping (String) -> String? = { GitInfo.branchName(inGitDir: $0) },
        gitRefreshFactory: @escaping GitRefreshFactory = { apply in
            GitRefreshCoordinator(apply: apply)
        }
    ) {
        self.readProcessCwd = readProcessCwd
        self.readRemoteIndicator = readRemoteIndicator
        self.findGitDir = findGitDir
        self.readBranch = readBranch
        self.gitRefreshFactory = gitRefreshFactory
    }

    /// Accepts a cwd reported by OSC 7 or libproc. Repository resolution and
    /// status scheduling happen only when the path actually changes.
    func updateCwd(_ path: String) {
        guard path != cwd else { return }
        cwd = path
        gitDir = path.isEmpty ? nil : findGitDir(path)

        if path.isEmpty {
            gitRefresh.cancel()
            setGitStatus(nil)
        } else {
            gitRefresh.schedule(path: path, reason: .cwdChanged)
        }
        onChange?(.cwd)
    }

    /// Refreshes cheap process context. Returns true while a remote client is
    /// active so `TerminalSession` can also discard a stale remote OSC title.
    @discardableResult
    func refresh(shellPid: Int32, foregroundProcessGroup: Int32?, isActive: Bool) -> Bool {
        let remote = readRemoteIndicator(shellPid, foregroundProcessGroup)
        setRemoteIndicator(remote)

        if remote != nil {
            updateCwd("")
            setBranch("")
            return true
        }

        if let path = readProcessCwd(shellPid) {
            updateCwd(path)
        }
        if isActive {
            setBranch(gitDir.flatMap(readBranch) ?? "")
        }
        return false
    }

    /// Handles the OSC 133 `D` side effects that belong to process context:
    /// refresh cwd immediately and schedule a strong git-status update.
    func commandFinished(shellPid: Int32) {
        sawCommandFinishedMark = true
        if let path = readProcessCwd(shellPid) {
            updateCwd(path)
        }
        if !cwd.isEmpty {
            gitRefresh.schedule(path: cwd, reason: .commandFinished)
        }
    }

    func tabActivated() {
        scheduleIfPossible(reason: .tabActivated)
    }

    func focusReturned() {
        scheduleIfPossible(reason: .focusReturned)
    }

    func fallbackRefreshGitStatusIfNeeded() {
        guard !sawCommandFinishedMark, !cwd.isEmpty, !branch.isEmpty else { return }
        gitRefresh.schedule(path: cwd, reason: .fallbackPoll)
    }

    private func scheduleIfPossible(reason: GitRefreshCoordinator.Reason) {
        guard !cwd.isEmpty else { return }
        gitRefresh.schedule(path: cwd, reason: reason)
    }

    private func setBranch(_ value: String) {
        guard value != branch else { return }
        branch = value
        onChange?(.branch)
    }

    private func setGitStatus(_ value: GitStatus?) {
        guard value != gitStatus else { return }
        gitStatus = value
        onChange?(.gitStatus)
    }

    private func setRemoteIndicator(_ value: String?) {
        guard value != remoteIndicator else { return }
        remoteIndicator = value
        onChange?(.remoteIndicator)
    }
}
