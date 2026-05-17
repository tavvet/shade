import AppKit
import SwiftUI

/// Lightweight reflection of TerminalsController for SwiftUI consumption.
@MainActor
final class TabsObservable: ObservableObject {
    @Published private(set) var tabs: [String] = []
    @Published private(set) var activeIndex: Int = 0

    private weak var controller: TerminalsController?

    init(controller: TerminalsController) {
        self.controller = controller
        sync()
        NotificationCenter.default.addObserver(
            forName: TerminalsController.tabsChanged,
            object: controller,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.sync() }
        }
    }

    private func sync() {
        guard let controller else { return }
        tabs = (1...max(1, controller.sessions.count)).map { String($0) }
        // If there are no sessions yet, keep a single placeholder so the bar isn't empty.
        if controller.sessions.isEmpty { tabs = [] }
        activeIndex = controller.activeIndex
    }
}

struct TabBarView: View {
    @ObservedObject var tabs: TabsObservable
    var onSelect: (Int) -> Void
    var onClose: (Int) -> Void
    var onNew: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(tabs.tabs.enumerated()), id: \.offset) { idx, title in
                TabChip(
                    title: title,
                    isActive: idx == tabs.activeIndex,
                    onClick: { onSelect(idx) },
                    onClose: { onClose(idx) }
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
            .help("New tab (⌃⌥T)")
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
