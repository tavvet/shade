import Foundation

/// Event-driven `git status` scheduler for a single terminal session.
///
/// Replaces the previous polling-every-second-on-active-tab approach: instead
/// of running `git status` on a fixed cadence, callers signal the coordinator
/// on events that *might* have changed the working tree, and the coordinator
/// decides whether to actually fork `git` after applying:
///
/// - **debounce** — a burst of `cd repo && git checkout … && git pull` only
///   triggers a single status update at the end of the burst.
/// - **cancel-previous** — new strong events or a changed path replace older
///   work. Weak events for the same path share its pending/in-flight refresh.
/// - **weak-reason rate-limit** — `tabActivated` / `focusReturned` events
///   shouldn't re-fork git if we already refreshed seconds ago and the repo
///   root hasn't changed. `cwdChanged` / `commandFinished` (strong) always
///   pass.
@MainActor
final class GitRefreshCoordinator {
    enum Reason: Equatable {
        case cwdChanged
        case commandFinished
        case tabActivated
        case focusReturned
        case fallbackPoll

        /// Strong reasons always run; weak ones are skipped when the repo
        /// root hasn't changed and the last refresh was recent.
        var isStrong: Bool {
            switch self {
            case .cwdChanged, .commandFinished: return true
            case .tabActivated, .focusReturned, .fallbackPoll: return false
            }
        }
    }

    typealias Fetcher = @Sendable (String) async -> GitStatusRefreshResult
    typealias Apply = @MainActor (GitStatus?) -> Void

    private let fetch: Fetcher
    private let apply: Apply
    private let debounce: Duration
    private let weakReasonCooldown: TimeInterval
    private let clock: () -> Date

    private var task: Task<Void, Never>?
    private var pendingPath: String?
    private var requestID: UUID?
    private var lastRefreshAt: Date?
    private var lastRoot: String?

    init(
        debounce: Duration = .milliseconds(350),
        weakReasonCooldown: TimeInterval = 5,
        clock: @escaping () -> Date = Date.init,
        fetch: @escaping Fetcher = { path in
            await GitInfo.statusCancellable(forCwd: path)
        },
        apply: @escaping Apply
    ) {
        self.debounce = debounce
        self.weakReasonCooldown = weakReasonCooldown
        self.clock = clock
        self.fetch = fetch
        self.apply = apply
    }

    func schedule(path: String, reason: Reason) {
        // A poll/focus event does not invalidate the work already underway.
        // Restarting its debounce/fetch on every 1 Hz poll would otherwise
        // prevent a slow repository from ever producing a status snapshot.
        if !reason.isStrong, task != nil, pendingPath == path {
            return
        }
        if !reason.isStrong,
           task == nil,
           let last = lastRefreshAt,
           clock().timeIntervalSince(last) < weakReasonCooldown,
           path == lastRoot {
            return
        }

        task?.cancel()
        let requestID = UUID()
        self.requestID = requestID
        pendingPath = path
        let debounce = self.debounce
        let fetch = self.fetch
        let apply = self.apply
        task = Task { @MainActor [weak self] in
            defer {
                // A cancelled fetch can finish after its replacement starts.
                // Only the current request may clear the coalescing state.
                if self?.requestID == requestID {
                    self?.task = nil
                    self?.pendingPath = nil
                    self?.requestID = nil
                }
            }
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }

            let result = await fetch(path)

            guard !Task.isCancelled else { return }
            let status: GitStatus?
            switch result {
            case let .status(value): status = value
            case .notRepository: status = nil
            case .failed:
                // Do not let an earlier successful refresh suppress the next
                // weak retry after a transient command failure.
                self?.lastRefreshAt = nil
                self?.lastRoot = nil
                return
            }
            self?.lastRefreshAt = self?.clock() ?? Date()
            self?.lastRoot = path
            apply(status)
        }
    }

    /// Called when the session loses its repo context entirely (e.g. cwd
    /// is no longer inside a repo, or session is being torn down). Cancels
    /// any pending refresh; the caller is expected to apply `nil` itself.
    func cancel() {
        task?.cancel()
        task = nil
        pendingPath = nil
        requestID = nil
        lastRefreshAt = nil
        lastRoot = nil
    }
}
