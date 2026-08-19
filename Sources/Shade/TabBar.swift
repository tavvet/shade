import SwiftUI

enum TabBarLayout {
    /// Ignores sub-point geometry noise so the native scroller does not flicker
    /// while SwiftUI settles the tab strip during a resize.
    private static let overflowTolerance: CGFloat = 1

    static func needsHorizontalScrolling(contentWidth: CGFloat,
                                         viewportWidth: CGFloat) -> Bool {
        guard viewportWidth > 0 else { return false }
        return contentWidth > viewportWidth + overflowTolerance
    }
}

struct TabBarView: View {
    @ObservedObject var tabs: TabsObservable
    @ObservedObject var inputSource: InputSourceMonitor
    var onSelect: (Int) -> Void
    var onClose: (Int) -> Void
    var onNew: () -> Void
    var onRename: (Int, String) -> Void
    var onEditEnd: () -> Void

    @State private var contentWidth: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0

    private var needsHorizontalScrolling: Bool {
        TabBarLayout.needsHorizontalScrolling(
            contentWidth: contentWidth,
            viewportWidth: viewportWidth
        )
    }

    var body: some View {
        HStack(spacing: 4) {
            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal, showsIndicators: needsHorizontalScrolling) {
                    HStack(spacing: 4) {
                        ForEach(tabs.tabs) { tab in
                            TabChip(
                                title: tab.label,
                                editableName: tab.editableName,
                                isActive: tab.index == tabs.activeIndex,
                                indicator: tab.indicator,
                                onClick: { onSelect(tab.index) },
                                onClose: { onClose(tab.index) },
                                onRename: { onRename(tab.index, $0) },
                                onEditEnd: onEditEnd
                            )
                            .id(tab.id)
                        }
                    }
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: TabBarContentWidthKey.self,
                                value: geometry.size.width
                            )
                        }
                    }
                }
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: TabBarViewportWidthKey.self,
                            value: geometry.size.width
                        )
                    }
                }
                .onPreferenceChange(TabBarContentWidthKey.self) { contentWidth = $0 }
                .onPreferenceChange(TabBarViewportWidthKey.self) { viewportWidth = $0 }
                .onChange(of: tabs.activeIndex) { _ in
                    scrollToActiveTab(using: scrollProxy)
                }
                .onChange(of: tabs.tabs.map(\.id)) { _ in
                    scrollToActiveTab(using: scrollProxy)
                }
                .onChange(of: needsHorizontalScrolling) { isNeeded in
                    if isNeeded { scrollToActiveTab(using: scrollProxy) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if inputSource.isEnabled {
                InputSourceBadge(inputSource: inputSource)
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
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(Color.black.opacity(0.55))
    }

    private func scrollToActiveTab(using scrollProxy: ScrollViewProxy) {
        guard tabs.tabs.indices.contains(tabs.activeIndex) else { return }
        let activeID = tabs.tabs[tabs.activeIndex].id
        withAnimation(.easeInOut(duration: 0.16)) {
            scrollProxy.scrollTo(activeID, anchor: .center)
        }
    }
}

private struct TabBarContentWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct TabBarViewportWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
