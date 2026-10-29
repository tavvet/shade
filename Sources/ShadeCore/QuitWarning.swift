import Foundation

/// Decides which tabs a quit asks about and how the question lists them.
public enum QuitWarning {
    public struct Tab: Equatable, Sendable {
        public let label: String
        public let isPinned: Bool
        /// The program running in place of the tab's shell, if any.
        public let program: String?

        public init(label: String, isPinned: Bool, program: String?) {
            self.label = label
            self.isPinned = isPinned
            self.program = program
        }
    }

    /// The tabs `setting` asks about, in tab order; empty means quit without asking.
    public static func tabs(_ tabs: [Tab], for setting: Preferences.QuitConfirmation) -> [Tab] {
        switch setting {
        case .never:
            return []
        case .pinnedTabs:
            return tabs.filter(\.isPinned)
        case .pinnedOrBusyTabs:
            return tabs.filter { $0.isPinned || $0.program != nil }
        }
    }

    public static func message(for tabs: [Tab]) -> String {
        let lines = tabs.map { "• " + description(of: $0) }
        return "Quitting closes these tabs and ends their processes:\n"
            + lines.joined(separator: "\n")
    }

    static func description(of tab: Tab) -> String {
        switch (tab.isPinned, tab.program) {
        case (true, let program?):
            return "\(tab.label) — pinned, running \(program)"
        case (true, nil):
            return "\(tab.label) — pinned"
        case (false, let program?):
            return "\(tab.label) — running \(program)"
        case (false, nil):
            return tab.label
        }
    }
}
