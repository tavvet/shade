import AppKit
import SwiftUI

/// One tab in the horizontal strip, including inline rename and status state.
struct TabChip: View {
    let title: String
    let editableName: String
    let isActive: Bool
    let indicator: TabIndicator
    let isPinned: Bool
    let minimumWidth: CGFloat
    let onClick: () -> Void
    let onClose: () -> Void
    let onTogglePin: () -> Void
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
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .frame(width: max(96, minimumWidth - 24))
                    .focused($fieldFocused)
                    .onSubmit(commit)
                    .onExitCommand(perform: cancel)
                    .onChange(of: fieldFocused) { focused in
                        if !focused { commit() }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
            } else {
                chipContent
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .frame(minWidth: minimumWidth)
                    .fixedSize(horizontal: true, vertical: false)
                    .contentShape(Rectangle())
                    // One single-tap gesture: a separate count-2 gesture makes
                    // SwiftUI hold every click (and the close button inside)
                    // for the double-click interval before acting.
                    .onTapGesture(perform: handleClick)
                    .help("Double-click to rename")
                    .contextMenu {
                        Button("Rename…", action: beginEditing)
                        if !editableName.isEmpty {
                            Button("Reset Name") { onRename("") }
                        }
                        Button(isPinned ? "Unpin Tab" : "Pin Tab", action: onTogglePin)
                        Divider()
                        Button("Close Tab", role: .destructive, action: onClose)
                            .disabled(isPinned)
                    }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isActive ? Color.white.opacity(0.18) : Color.white.opacity(hovering ? 0.08 : 0.0))
        )
        .onHover { hovering = $0 }
    }

    private var chipContent: some View {
        HStack(spacing: 6) {
            if indicator != .none {
                Circle()
                    .fill(indicator == .failed ? Color.red.opacity(0.9) : Color.white.opacity(0.55))
                    .frame(width: 6, height: 6)
                    .help(indicator == .failed ? "Last command failed" : "New output")
            }
            Text(title)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .foregroundStyle(.white.opacity(isActive ? 1.0 : 0.7))
            Spacer(minLength: 0)
            if isPinned {
                Button(action: onTogglePin) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(45))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help("Pinned — click to unpin (⌘⇧K)")
                .accessibilityLabel("Unpin tab")
            } else {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(hovering || isActive ? 0.8 : 0.0))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help("Close tab")
            }
        }
    }

    private func handleClick() {
        if ConnectionsSettingsClickEvent.isDoubleClick(NSApp.currentEvent) {
            beginEditing()
        } else {
            onClick()
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
