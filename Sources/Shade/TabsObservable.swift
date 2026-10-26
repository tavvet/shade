import Combine
import Foundation
import ShadeCore

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
        let isPinned: Bool
    }

    @Published private(set) var tabs: [TabInfo] = []
    @Published private(set) var activeIndex: Int = -1
    @Published private(set) var activeBranch: String = ""
    @Published private(set) var activeStatus: GitStatus? = nil

    private weak var controller: TerminalsController?

    /// Refreshes synchronously on every tab change until this projection is
    /// released; other observers of the same controller are unaffected.
    init(controller: TerminalsController) {
        self.controller = controller
        sync()
        controller.observeTabs(by: self) { $0.sync() }
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
                ),
                isPinned: controller.isPinned(at: index)
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
