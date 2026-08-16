import SwiftUI

struct SSHConnectionPickerRow: View {
    let profile: SSHProfile
    let quickSlot: Int?
    let isSelected: Bool
    let onHover: (Bool) -> Void
    let onConnect: () -> Void

    var body: some View {
        Button(action: onConnect) {
            HStack(spacing: 12) {
                Image(systemName: "server.rack")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 28, height: 28)
                    .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.name)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Text(SSHProfileDisplay.destinationLabel(profile))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let quickSlot {
                    Text("⌘⇧\(quickSlot)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                isSelected ? Color.accentColor.opacity(0.14) : .clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
        .buttonStyle(.plain)
        .onHover(perform: onHover)
    }
}

struct SSHConnectionPickerEmptyLibrary: View {
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: "server.rack")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text("No Saved Connections")
                .font(.headline)
            Text("Add a server in Settings to connect from here.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Open Settings…", action: onOpenSettings)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, minHeight: 210)
    }
}

struct SSHConnectionPickerNoResults: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 25, weight: .light))
                .foregroundStyle(.secondary)
            Text("No Matching Connections")
                .font(.headline)
            Text("Try a different name, host or user.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}

struct SSHConnectionPickerProblemBanner: View {
    let problem: SSHConnectionsProblem
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(problem.message)
                .font(.caption)
                .lineLimit(2)
            Spacer()

            if problem.kind == .load {
                Button("Retry", action: onRetry)
            } else {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(9)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct SSHConnectionPickerFooter: View {
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Text("↑↓ Select")
            Text("↩ Connect")
            Text("esc Close")
            Spacer()
            Button("Settings…", action: onOpenSettings)
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}
