import AppKit
import SwiftUI

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
        let id: Int
        let label: String
        let editableName: String
        let indicator: TabIndicator
    }

    @Published private(set) var tabs: [TabInfo] = []
    @Published private(set) var activeIndex: Int = -1
    @Published private(set) var activeBranch: String = ""
    @Published private(set) var activeStatus: GitStatus? = nil

    private weak var controller: TerminalsController?

    init(controller: TerminalsController) {
        self.controller = controller
        sync()
        let center = NotificationCenter.default
        center.addObserver(forName: TerminalsController.tabsChanged,
                           object: controller,
                           queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sync() }
        }
        center.addObserver(forName: TerminalSession.titleDidChange,
                           object: nil,
                           queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sync() }
        }
    }

    private func sync() {
        guard let controller else { return }
        tabs = controller.sessions.enumerated().map { idx, session in
            TabInfo(id: idx,
                    label: Self.formatLabel(index: idx, title: session.displayTitle),
                    editableName: session.userTitle ?? "",
                    indicator: Self.indicator(lastExitCode: session.lastExitCode,
                                              hasUnseenActivity: session.hasUnseenActivity))
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
        let maxLen = 24
        let truncated = clean.count > maxLen ? "…" + String(clean.suffix(maxLen)) : clean
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

struct TabBarView: View {
    @ObservedObject var tabs: TabsObservable
    var onSelect: (Int) -> Void
    var onClose: (Int) -> Void
    var onNew: () -> Void
    var onRename: (Int, String) -> Void
    var onEditEnd: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs.tabs) { tab in
                TabChip(
                    title: tab.label,
                    editableName: tab.editableName,
                    isActive: tab.id == tabs.activeIndex,
                    indicator: tab.indicator,
                    onClick: { onSelect(tab.id) },
                    onClose: { onClose(tab.id) },
                    onRename: { onRename(tab.id, $0) },
                    onEditEnd: onEditEnd
                )
            }
            Button(action: onNew) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
            }
            .buttonStyle(.plain)
            .help("New tab (⌘T)")
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(Color.black.opacity(0.55))
    }
}

private struct TabChip: View {
    let title: String
    let editableName: String
    let isActive: Bool
    let indicator: TabIndicator
    let onClick: () -> Void
    let onClose: () -> Void
    let onRename: (String) -> Void
    let onEditEnd: () -> Void

    @State private var hovering = false
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        Group {
            if editing {
                TextField("Tab name", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
                    .frame(width: 96)
                    .focused($fieldFocused)
                    .onSubmit(commit)
                    .onExitCommand(perform: cancel)
                    .onChange(of: fieldFocused) { focused in
                        if !focused { commit() }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
            } else {
                chipContent
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2, perform: beginEditing)
                    .onTapGesture(perform: onClick)
                    .help("Double-click to rename")
                    .contextMenu {
                        Button("Rename…", action: beginEditing)
                        if !editableName.isEmpty {
                            Button("Reset Name") { onRename("") }
                        }
                    }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isActive ? Color.white.opacity(0.18) : Color.white.opacity(hovering ? 0.08 : 0.0))
        )
        .onHover { hovering = $0 }
    }

    private var chipContent: some View {
        HStack(spacing: 4) {
            if indicator != .none {
                Circle()
                    .fill(indicator == .failed ? Color.red.opacity(0.9) : Color.white.opacity(0.55))
                    .frame(width: 6, height: 6)
                    .help(indicator == .failed ? "Last command failed" : "New output")
            }
            Text(title)
                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                .foregroundStyle(.white.opacity(isActive ? 1.0 : 0.7))
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(hovering || isActive ? 0.8 : 0.0))
                    .frame(width: 12, height: 12)
            }
            .buttonStyle(.plain)
            .help("Close tab")
        }
    }

    private func beginEditing() {
        draft = editableName
        editing = true
        DispatchQueue.main.async { fieldFocused = true }
    }

    private func commit() {
        guard editing else { return }
        editing = false
        onRename(draft)
        onEditEnd()
    }

    private func cancel() {
        guard editing else { return }
        editing = false
        onEditEnd()
    }
}
