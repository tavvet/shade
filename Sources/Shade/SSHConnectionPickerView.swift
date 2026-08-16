import SwiftUI

struct SSHConnectionPickerView: View {
    @ObservedObject var controller: SSHConnectionsController
    @ObservedObject var focusRequest: SSHConnectionPickerFocusRequest

    let onConnect: (UUID) -> Void
    let onDismiss: () -> Void
    let onManage: () -> Void

    @State private var query = ""
    @State private var selectedID: UUID?
    @FocusState private var searchIsFocused: Bool

    private var matches: [SSHProfile] {
        SSHConnectionPickerSearch.matches(controller.profiles, query: query)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.34)
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 0) {
                header
                searchField
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)

                if let problem = controller.problem {
                    SSHConnectionPickerProblemBanner(
                        problem: problem,
                        onRetry: controller.reload,
                        onDismiss: controller.dismissProblem
                    )
                        .padding(.horizontal, 18)
                        .padding(.bottom, 10)
                }

                pickerContent
                    .padding(.horizontal, 10)

                Divider()
                    .padding(.top, 10)
                SSHConnectionPickerFooter(onOpenSettings: onManage)
            }
            .frame(maxWidth: 560)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.white.opacity(0.12))
            }
            .shadow(color: .black.opacity(0.32), radius: 28, y: 12)
            .padding(36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            repairSelection()
            requestSearchFocus()
        }
        .onChange(of: focusRequest.generation) { _ in requestSearchFocus() }
        .onChange(of: matches.map(\.id)) { _ in repairSelection() }
        .onExitCommand(perform: onDismiss)
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: "network")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 32, height: 32)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 1) {
                Text("Connect to Server")
                    .font(.headline)
                Text("Saved SSH connections")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(18)
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search by name, host, user, port or key", text: $query)
                .textFieldStyle(.plain)
                .focused($searchIsFocused)
                .onSubmit(connectSelected)
                .onMoveCommand(perform: moveSelection)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 38)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.8),
            in: RoundedRectangle(cornerRadius: 9)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(searchIsFocused ? Color.accentColor.opacity(0.7) : .secondary.opacity(0.18))
        }
    }

    @ViewBuilder
    private var pickerContent: some View {
        if controller.profiles.isEmpty {
            SSHConnectionPickerEmptyLibrary(onOpenSettings: onManage)
        } else if matches.isEmpty {
            SSHConnectionPickerNoResults()
        } else {
            connectionList
        }
    }

    private var connectionList: some View {
        let resultIDs = matches.map(\.id)
        return ScrollViewReader { proxy in
            ScrollView {
                // The saved-connection library is small, and an eager stack avoids
                // stale macOS LazyVStack geometry while the filtered IDs change.
                VStack(spacing: 4) {
                    ForEach(matches) { profile in
                        SSHConnectionPickerRow(
                            profile: profile,
                            quickSlot: quickSlot(for: profile),
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
            .onChange(of: selectedID) { id in
                guard let id else { return }
                // Selection repair and filtered-row layout happen in one SwiftUI
                // transaction. Scroll only after the new subtree has been laid out.
                DispatchQueue.main.async {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
        .id(resultIDs)
    }

    private func quickSlot(for profile: SSHProfile) -> Int? {
        guard let index = controller.profiles.firstIndex(where: { $0.id == profile.id }),
              index < 9 else { return nil }
        return index + 1
    }

    private func repairSelection() {
        if let selectedID, matches.contains(where: { $0.id == selectedID }) {
            return
        }
        selectedID = matches.first?.id
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        let offset: Int
        switch direction {
        case .up: offset = -1
        case .down: offset = 1
        default: return
        }

        let ids = matches.map(\.id)
        guard !ids.isEmpty else { return }
        guard let selectedID, let current = ids.firstIndex(of: selectedID) else {
            self.selectedID = offset > 0 ? ids.first : ids.last
            return
        }
        self.selectedID = ids[min(max(0, current + offset), ids.count - 1)]
    }

    private func connectSelected() {
        guard let selectedID else { return }
        onConnect(selectedID)
    }

    private func requestSearchFocus() {
        DispatchQueue.main.async { searchIsFocused = true }
    }
}
