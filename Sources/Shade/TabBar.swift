import AppKit
import SwiftUI

/// Lightweight reflection of TerminalsController for SwiftUI consumption.
@MainActor
final class TabsObservable: ObservableObject {
    struct TabInfo: Identifiable {
        let id: Int
        let label: String
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
            TabInfo(id: idx, label: Self.formatLabel(index: idx, title: session.displayTitle))
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
}

struct TabBarView: View {
    @ObservedObject var tabs: TabsObservable
    var onSelect: (Int) -> Void
    var onClose: (Int) -> Void
    var onNew: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs.tabs) { tab in
                TabChip(
                    title: tab.label,
                    isActive: tab.id == tabs.activeIndex,
                    onClick: { onSelect(tab.id) },
                    onClose: { onClose(tab.id) }
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
    let isActive: Bool
    let onClick: () -> Void
    let onClose: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
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
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isActive ? Color.white.opacity(0.18) : Color.white.opacity(hovering ? 0.08 : 0.0))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onClick)
        .onHover { hovering = $0 }
    }
}
