import SwiftUI

struct ConnectionsSettingsList: View {
    let profiles: [SSHProfile]
    @Binding var selectedID: UUID?
    let canEditProfiles: Bool
    let onConnect: (UUID) -> Void
    let onEdit: (SSHProfile) -> Void
    let onDelete: (SSHProfile) -> Void

    var body: some View {
        List(selection: $selectedID) {
            ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                ConnectionsSettingsRow(profile: profile, quickSlot: index + 1)
                    .tag(profile.id)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { onEdit(profile) }
                    .contextMenu {
                        Button("Connect") { onConnect(profile.id) }
                        Button("Edit…") { onEdit(profile) }
                            .disabled(!canEditProfiles)
                        Divider()
                        Button("Delete…", role: .destructive) { onDelete(profile) }
                            .disabled(!canEditProfiles)
                    }
            }
        }
        .listStyle(.inset)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

private struct ConnectionsSettingsRow: View {
    let profile: SSHProfile
    let quickSlot: Int

    var body: some View {
        HStack(spacing: 12) {
            Text("\(quickSlot)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                Text(profile.name)
                    .fontWeight(.medium)
                Text(SSHProfileDisplay.destinationLabel(profile))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let identityFile = profile.identityFile {
                Image(systemName: "key")
                    .foregroundStyle(.secondary)
                    .help(identityFile)
            }
        }
        .padding(.vertical, 5)
    }
}

struct ConnectionsSettingsEmptyState: View {
    let canEditProfiles: Bool
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "network")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text("No Saved Connections")
                .font(.title3.weight(.semibold))
            Text("Add a server or an alias from ~/.ssh/config.")
                .foregroundStyle(.secondary)
            Button("Add Connection…", action: onAdd)
                .disabled(!canEditProfiles)
        }
    }
}

struct ConnectionsSettingsControls: View {
    let hasSelection: Bool
    let canEditProfiles: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onAdd: () -> Void
    let onDelete: () -> Void
    let onEdit: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onConnect: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onAdd) {
                Image(systemName: "plus")
            }
            .help("Add connection")
            .disabled(!canEditProfiles)

            Button(action: onDelete) {
                Image(systemName: "minus")
            }
            .help("Delete connection")
            .disabled(!hasSelection || !canEditProfiles)

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .help("Edit connection")
            .disabled(!hasSelection || !canEditProfiles)

            Divider()
                .frame(height: 18)

            Button(action: onMoveUp) {
                Image(systemName: "arrow.up")
            }
            .help("Move connection up")
            .disabled(!canMoveUp || !canEditProfiles)

            Button(action: onMoveDown) {
                Image(systemName: "arrow.down")
            }
            .help("Move connection down")
            .disabled(!canMoveDown || !canEditProfiles)

            Spacer()

            Button("Connect", action: onConnect)
                .disabled(!hasSelection)
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

struct ConnectionsSettingsProblemBanner: View {
    let problem: SSHConnectionsProblem
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(problem.message)
                .font(.callout)
                .lineLimit(2)
            Spacer()
            if problem.kind == .load {
                Button("Retry", action: onRetry)
            } else {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
        }
        .padding(10)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ConnectionsSettingsOperationProblemBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.callout)
                .lineLimit(2)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(10)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}
