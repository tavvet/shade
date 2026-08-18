import SwiftUI

struct ConnectionsSettingsView: View {
    @ObservedObject var controller: SSHConnectionsController
    @StateObject private var state = ConnectionsSettingsViewState()

    private var selectedProfile: SSHProfile? {
        state.selectedProfile(in: controller.profiles)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let problem = controller.problem {
                ConnectionsSettingsProblemBanner(
                    problem: problem,
                    onRetry: controller.reload,
                    onDismiss: controller.dismissProblem
                )
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            if let operationError = state.operationError {
                ConnectionsSettingsOperationProblemBanner(
                    message: operationError,
                    onDismiss: state.dismissOperationError
                )
                .padding(.horizontal, 20)
                .padding(.top, 10)
            }

            if controller.profiles.isEmpty {
                ConnectionsSettingsEmptyState(
                    canEditProfiles: controller.canEditProfiles,
                    onAdd: beginAdding
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ConnectionsSettingsList(
                    profiles: controller.profiles,
                    selectedID: $state.selectedID,
                    canEditProfiles: controller.canEditProfiles,
                    onConnect: { controller.connect(to: $0) },
                    onEdit: beginEditing,
                    onDelete: state.requestDeletion
                )
            }

            Divider()
            controls
        }
        .onAppear(perform: repairSelection)
        .onChange(of: controller.profiles.map(\.id)) { _ in repairSelection() }
        .sheet(item: $state.editor) { context in
            SSHProfileEditorView(
                profile: context.profile,
                isNew: context.isNew
            ) { profile in
                try state.save(profile, context: context, using: controller)
            }
        }
        .alert(
            "Delete Connection?",
            isPresented: deletionAlertIsPresented,
            presenting: state.pendingDeletion
        ) { profile in
            Button("Delete", role: .destructive) {
                state.remove(profile, using: controller)
            }
            Button("Cancel", role: .cancel) {}
        } message: { profile in
            Text("\"\(profile.name)\" will be removed from Shade. "
                 + "Your SSH config and keys are unaffected.")
        }
    }

    private var controls: some View {
        ConnectionsSettingsControls(
            hasSelection: selectedProfile != nil,
            canEditProfiles: controller.canEditProfiles,
            canMoveUp: state.canMoveSelected(in: controller.profiles, by: -1),
            canMoveDown: state.canMoveSelected(in: controller.profiles, by: 1),
            onAdd: beginAdding,
            onDelete: {
                if let selectedProfile { state.requestDeletion(of: selectedProfile) }
            },
            onEdit: {
                if let selectedProfile { beginEditing(selectedProfile) }
            },
            onMoveUp: { state.moveSelected(using: controller, by: -1) },
            onMoveDown: { state.moveSelected(using: controller, by: 1) },
            onConnect: {
                if let selectedID = state.selectedID { controller.connect(to: selectedID) }
            }
        )
    }

    private func beginAdding() {
        state.beginAdding(canEditProfiles: controller.canEditProfiles)
    }

    private func beginEditing(_ profile: SSHProfile) {
        state.beginEditing(profile, canEditProfiles: controller.canEditProfiles)
    }

    private func repairSelection() {
        state.repairSelection(in: controller.profiles)
    }

    private var deletionAlertIsPresented: Binding<Bool> {
        Binding(
            get: { state.pendingDeletion != nil },
            set: { if !$0 { state.dismissDeletion() } }
        )
    }
}
