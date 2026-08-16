import SwiftUI

struct ConnectionsSettingsView: View {
    @ObservedObject var controller: SSHConnectionsController

    @State private var selectedID: UUID?
    @State private var editor: SSHProfileEditorContext?
    @State private var pendingDeletion: SSHProfile?
    @State private var operationError: String?

    private var selectedProfile: SSHProfile? {
        guard let selectedID else { return nil }
        return controller.profiles.first(where: { $0.id == selectedID })
    }

    var body: some View {
        VStack(spacing: 0) {
            if let problem = controller.problem {
                problemBanner(problem)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
            }
            if let operationError {
                operationProblemBanner(operationError)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
            }

            if controller.profiles.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                connectionList
            }

            Divider()
            controls
        }
        .onAppear(perform: repairSelection)
        .onChange(of: controller.profiles.map(\.id)) { _ in repairSelection() }
        .sheet(item: $editor) { context in
            SSHProfileEditorView(
                profile: context.profile,
                isNew: context.isNew
            ) { profile in
                if context.isNew {
                    try controller.add(profile)
                } else {
                    try controller.update(profile)
                }
                selectedID = profile.id
            }
        }
        .alert(
            "Delete Connection?",
            isPresented: deletionAlertIsPresented,
            presenting: pendingDeletion
        ) { profile in
            Button("Delete", role: .destructive) { remove(profile) }
            Button("Cancel", role: .cancel) {}
        } message: { profile in
            Text("\"\(profile.name)\" will be removed from Shade. "
                 + "Your SSH config and keys are unaffected.")
        }
    }

    private var connectionList: some View {
        List(selection: $selectedID) {
            ForEach(controller.profiles) { profile in
                connectionRow(profile)
                    .tag(profile.id)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { edit(profile) }
                    .contextMenu {
                        Button("Connect") { controller.connect(to: profile.id) }
                        Button("Edit…") { edit(profile) }
                        Divider()
                        Button("Delete…", role: .destructive) {
                            pendingDeletion = profile
                        }
                    }
            }
        }
        .listStyle(.inset)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func connectionRow(_ profile: SSHProfile) -> some View {
        let index = controller.profiles.firstIndex(where: { $0.id == profile.id }) ?? 0
        return HStack(spacing: 12) {
            Text("\(index + 1)")
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

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "network")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text("No Saved Connections")
                .font(.title3.weight(.semibold))
            Text("Add a server or an alias from ~/.ssh/config.")
                .foregroundStyle(.secondary)
            Button("Add Connection…", action: add)
                .disabled(!controller.canEditProfiles)
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button(action: add) {
                Image(systemName: "plus")
            }
            .help("Add connection")
            .disabled(!controller.canEditProfiles)

            Button {
                if let selectedProfile { pendingDeletion = selectedProfile }
            } label: {
                Image(systemName: "minus")
            }
            .help("Delete connection")
            .disabled(selectedProfile == nil || !controller.canEditProfiles)

            Button {
                if let selectedProfile { edit(selectedProfile) }
            } label: {
                Image(systemName: "pencil")
            }
            .help("Edit connection")
            .disabled(selectedProfile == nil || !controller.canEditProfiles)

            Divider()
                .frame(height: 18)

            Button { moveSelected(by: -1) } label: {
                Image(systemName: "arrow.up")
            }
            .help("Move connection up")
            .disabled(!canMoveSelected(by: -1) || !controller.canEditProfiles)

            Button { moveSelected(by: 1) } label: {
                Image(systemName: "arrow.down")
            }
            .help("Move connection down")
            .disabled(!canMoveSelected(by: 1) || !controller.canEditProfiles)

            Spacer()

            Button("Connect") {
                if let selectedID { controller.connect(to: selectedID) }
            }
            .disabled(selectedProfile == nil)
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func problemBanner(_ problem: SSHConnectionsProblem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(problem.message)
                .font(.callout)
                .lineLimit(2)
            Spacer()
            if problem.kind == .load {
                Button("Retry", action: controller.reload)
            } else {
                Button {
                    controller.dismissProblem()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
        }
        .padding(10)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private func operationProblemBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.callout)
                .lineLimit(2)
            Spacer()
            Button {
                operationError = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(10)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func add() {
        editor = SSHProfileEditorContext(
            profile: SSHProfile(name: "", host: ""),
            isNew: true
        )
    }

    private func edit(_ profile: SSHProfile) {
        editor = SSHProfileEditorContext(profile: profile, isNew: false)
    }

    private func remove(_ profile: SSHProfile) {
        do {
            try controller.remove(id: profile.id)
        } catch {
            operationError = error.localizedDescription
        }
        pendingDeletion = nil
    }

    private func canMoveSelected(by offset: Int) -> Bool {
        guard let selectedProfile,
              let index = controller.profiles.firstIndex(where: { $0.id == selectedProfile.id }) else {
            return false
        }
        return controller.profiles.indices.contains(index + offset)
    }

    private func moveSelected(by offset: Int) {
        guard let selectedProfile,
              let index = controller.profiles.firstIndex(where: { $0.id == selectedProfile.id }) else {
            return
        }
        do {
            try controller.move(id: selectedProfile.id, to: index + offset)
        } catch {
            operationError = error.localizedDescription
        }
    }

    private func repairSelection() {
        if let selectedID, controller.profiles.contains(where: { $0.id == selectedID }) {
            return
        }
        selectedID = controller.profiles.first?.id
    }

    private var deletionAlertIsPresented: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }

}

enum SSHProfileDisplay {
    static func destinationLabel(_ profile: SSHProfile) -> String {
        var host = profile.host
        if profile.port != nil, host.contains(":"), !host.hasPrefix("[") {
            host = "[\(host)]"
        }
        let destination = profile.username.map { "\($0)@\(host)" } ?? host
        return profile.port.map { "\(destination):\($0)" } ?? destination
    }
}

private struct SSHProfileEditorContext: Identifiable {
    let profile: SSHProfile
    let isNew: Bool

    var id: UUID { profile.id }
}
