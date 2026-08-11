import Combine
import Foundation

/// What the small status dot on a tab chip signals.
enum TabIndicator: Equatable {
    case none
    case activity   // a background tab produced output you haven't seen yet
    case failed     // the last command exited non-zero (requires OSC 133)
}

/// Lightweight reflection of TerminalsController for SwiftUI consumption.
@MainActor
final class TabsObservable: ObservableObject {
    struct TabInfo: Identifiable {
        let id: UUID
        let index: Int
        let label: String
        let editableName: String
        let indicator: TabIndicator
    }

    @Published private(set) var tabs: [TabInfo] = []
    @Published private(set) var activeIndex: Int = -1
    @Published private(set) var activeBranch: String = ""
    @Published private(set) var activeStatus: GitStatus? = nil

    private weak var controller: TerminalsController?
    private let observations: NotificationObservationBag

    init(
        controller: TerminalsController,
        notificationCenter: NotificationCenter = .default
    ) {
        self.controller = controller
        let observations = NotificationObservationBag(center: notificationCenter)
        self.observations = observations
        sync()
        observations.add(
            notificationCenter.addObserver(
                forName: TerminalsController.tabsChanged,
                object: controller,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.sync() }
            }
        )
        observations.add(
            notificationCenter.addObserver(
                forName: TerminalSession.titleDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.sync() }
            }
        )
    }

    private func sync() {
        guard let controller else { return }
        tabs = controller.sessions.enumerated().map { index, session in
            TabInfo(
                id: session.id,
                index: index,
                label: Self.formatLabel(index: index, title: session.displayTitle),
                editableName: session.userTitle ?? "",
                indicator: Self.indicator(
                    lastExitCode: session.lastExitCode,
                    hasUnseenActivity: session.hasUnseenActivity
                )
            )
        }
        activeIndex = controller.activeIndex
        let active = controller.activeSession
        // Hide branch / status when we're inside an ssh / mosh session — the local
        // values describe the wrong machine.
        if active?.remoteIndicator != nil {
            activeBranch = ""
            activeStatus = nil
        } else {
            activeBranch = active?.branch ?? ""
            activeStatus = active?.gitStatus
        }
    }

    static func formatLabel(index: Int, title: String) -> String {
        let number = "\(index + 1)"
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return number }
        let maxLength = 24
        let truncated = clean.count > maxLength ? "…" + String(clean.suffix(maxLength)) : clean
        return "\(number) · \(truncated)"
    }

    /// Maps a session's command/activity state to its tab dot. A non-zero exit
    /// (failure) takes priority over unseen activity.
    static func indicator(lastExitCode: Int?, hasUnseenActivity: Bool) -> TabIndicator {
        if let code = lastExitCode, code != 0 { return .failed }
        if hasUnseenActivity { return .activity }
        return .none
    }
}

/// Owns Objective-C notification tokens outside MainActor isolation. Tokens
/// are only appended during TabsObservable initialization, then removed when
/// the bag follows its owner out of scope.
private final class NotificationObservationBag: @unchecked Sendable {
    private let center: NotificationCenter
    private var tokens: [NSObjectProtocol] = []

    init(center: NotificationCenter) {
        self.center = center
    }

    func add(_ token: NSObjectProtocol) {
        tokens.append(token)
    }

    deinit {
        for token in tokens {
            center.removeObserver(token)
        }
    }
}
