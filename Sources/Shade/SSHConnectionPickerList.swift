import SwiftUI

struct SSHConnectionPickerList: View {
    let matches: [SSHProfile]
    @Binding var selectedID: UUID?
    let quickSlot: (SSHProfile) -> Int?
    let onConnect: (UUID) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // An eager stack avoids stale macOS LazyVStack geometry while
                // the small saved-connection library is filtered.
                VStack(spacing: 4) {
                    ForEach(matches) { profile in
                        SSHConnectionPickerRow(
                            profile: profile,
                            quickSlot: quickSlot(profile),
                            isSelected: selectedID == profile.id,
                            onHover: { hovering in
                                if hovering { selectedID = profile.id }
                            },
                            onConnect: { onConnect(profile.id) }
                        )
                        .id(profile.id)
                    }
                }
                .padding(4)
            }
            .frame(minHeight: 150, idealHeight: 250, maxHeight: 300)
            .background(
                Color(nsColor: .controlBackgroundColor).opacity(0.45),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .onAppear { scrollToSelection(using: proxy) }
            .onChange(of: selectedID) { _ in scrollToSelection(using: proxy) }
        }
        .id(matches.map(\.id))
    }

    private func scrollToSelection(using proxy: ScrollViewProxy) {
        guard let selectedID, matches.contains(where: { $0.id == selectedID }) else { return }
        // Filtering recreates this scroll view even when the selection survives.
        // Wait for the new rows to be laid out before restoring its position.
        DispatchQueue.main.async {
            proxy.scrollTo(selectedID, anchor: .center)
        }
    }
}
