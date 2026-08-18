import Combine
import Foundation

/// Owns the transient interaction state for the Connections settings page.
/// Persisted profiles remain the responsibility of `SSHConnectionsController`;
/// this object only coordinates selection, editor/deletion presentation and
/// operation-level errors.
@MainActor
final class ConnectionsSettingsViewState: ObservableObject {
    @Published var selectedID: UUID?
    @Published var editor: SSHProfileEditorContext?
    @Published var pendingDeletion: SSHProfile?
    @Published var operationError: String?

    func selectedProfile(in profiles: [SSHProfile]) -> SSHProfile? {
        guard let selectedID else { return nil }
        return profiles.first(where: { $0.id == selectedID })
    }

    func repairSelection(in profiles: [SSHProfile]) {
        if let selectedID, profiles.contains(where: { $0.id == selectedID }) {
            return
        }
        selectedID = profiles.first?.id
    }

    func beginAdding(canEditProfiles: Bool) {
        guard canEditProfiles else { return }
        editor = SSHProfileEditorContext(
            profile: SSHProfile(name: "", host: ""),
            isNew: true
        )
    }

    func beginEditing(_ profile: SSHProfile, canEditProfiles: Bool) {
        guard canEditProfiles else { return }
        editor = SSHProfileEditorContext(profile: profile, isNew: false)
    }

    func requestDeletion(of profile: SSHProfile) {
        pendingDeletion = profile
    }

    func dismissDeletion() {
        pendingDeletion = nil
    }

    func dismissOperationError() {
        operationError = nil
    }

    func save(
        _ profile: SSHProfile,
        context: SSHProfileEditorContext,
        using controller: SSHConnectionsController
    ) throws {
        do {
            if context.isNew {
                try controller.add(profile)
            } else {
                try controller.update(profile)
            }
        } catch {
            if ConnectionsSettingsErrorPresentation.isMatchingSaveProblem(
                error.localizedDescription,
                reportedProblem: controller.problem
            ) {
                // The editor keeps the sheet open and renders this error inline.
                controller.dismissProblem()
            }
            throw error
        }

        operationError = nil
        selectedID = profile.id
    }

    func remove(_ profile: SSHProfile, using controller: SSHConnectionsController) {
        do {
            try controller.remove(id: profile.id)
            operationError = nil
        } catch {
            operationError = ConnectionsSettingsErrorPresentation.operationMessage(
                error.localizedDescription,
                reportedProblem: controller.problem
            )
        }
        pendingDeletion = nil
    }

    func canMoveSelected(in profiles: [SSHProfile], by offset: Int) -> Bool {
        guard let selectedProfile = selectedProfile(in: profiles),
              let index = profiles.firstIndex(where: { $0.id == selectedProfile.id }) else {
            return false
        }
        return profiles.indices.contains(index + offset)
    }

    func moveSelected(using controller: SSHConnectionsController, by offset: Int) {
        guard let selectedProfile = selectedProfile(in: controller.profiles),
              let index = controller.profiles.firstIndex(where: { $0.id == selectedProfile.id }) else {
            return
        }
        do {
            try controller.move(id: selectedProfile.id, to: index + offset)
            operationError = nil
        } catch {
            operationError = ConnectionsSettingsErrorPresentation.operationMessage(
                error.localizedDescription,
                reportedProblem: controller.problem
            )
        }
    }
}

struct SSHProfileEditorContext: Identifiable, Equatable {
    let profile: SSHProfile
    let isNew: Bool

    var id: UUID { profile.id }
}

enum ConnectionsSettingsErrorPresentation {
    static func isMatchingSaveProblem(
        _ message: String,
        reportedProblem: SSHConnectionsProblem?
    ) -> Bool {
        reportedProblem == SSHConnectionsProblem(kind: .save, message: message)
    }

    static func operationMessage(
        _ message: String,
        reportedProblem: SSHConnectionsProblem?
    ) -> String? {
        guard !isMatchingSaveProblem(message, reportedProblem: reportedProblem) else {
            return nil
        }
        return message
    }
}
