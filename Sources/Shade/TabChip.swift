import SwiftUI

/// One tab in the horizontal strip, including inline rename and status state.
struct TabChip: View {
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
