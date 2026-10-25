import Foundation

/// Coalesces preference-change announcements. A request is posted on a later
/// main-actor turn, never inside the caller's storage transaction. The first
/// change in a quiet period goes out at once; during a burst, such as a slider
/// drag, posts are spaced at least `interval` apart, and the last request
/// always produces a post so observers apply the final values.
@MainActor
final class PreferencesChangeAnnouncer {
    private let interval: Duration
    private let post: @MainActor () -> Void
    private let clock = ContinuousClock()
    private var lastPost: ContinuousClock.Instant?
    private var pending: Task<Void, Never>?

    init(interval: Duration, post: @escaping @MainActor () -> Void) {
        self.interval = interval
        self.post = post
    }

    func request() {
        // A scheduled post reads the latest values when it fires, so it also
        // covers every request made before then.
        guard pending == nil else { return }
        pending = Task { @MainActor [weak self] in
            guard let self else { return }
            if let lastPost {
                let next = lastPost.advanced(by: interval)
                if next > clock.now { try? await clock.sleep(until: next) }
            }
            pending = nil
            lastPost = clock.now
            post()
        }
    }

    /// Waits until a scheduled post has been delivered.
    func waitForPending() async {
        await pending?.value
    }
}
