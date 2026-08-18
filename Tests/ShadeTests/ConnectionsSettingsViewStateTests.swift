import XCTest
@testable import Shade

final class ConnectionsSettingsViewStateTests: XCTestCase {
    func testRepairSelectionKeepsAValidSelectionAndFallsBackToFirstProfile() async {
        await MainActor.run {
            let first = SSHProfile(name: "First", host: "first")
            let second = SSHProfile(name: "Second", host: "second")
            let state = ConnectionsSettingsViewState()

            state.repairSelection(in: [first, second])
            XCTAssertEqual(state.selectedID, first.id)

            state.selectedID = second.id
            state.repairSelection(in: [first, second])
            XCTAssertEqual(state.selectedID, second.id)

            state.repairSelection(in: [first])
            XCTAssertEqual(state.selectedID, first.id)

            state.repairSelection(in: [])
            XCTAssertNil(state.selectedID)
        }
    }

    func testEditorRequestsRespectProfileEditingAvailability() async {
        await MainActor.run {
            let profile = SSHProfile(name: "Production", host: "prod")
            let state = ConnectionsSettingsViewState()

            state.beginAdding(canEditProfiles: false)
            XCTAssertNil(state.editor)

            state.beginAdding(canEditProfiles: true)
            XCTAssertEqual(state.editor?.isNew, true)
            XCTAssertEqual(state.editor?.profile.name, "")

            state.editor = nil
            state.beginEditing(profile, canEditProfiles: false)
            XCTAssertNil(state.editor)

            state.beginEditing(profile, canEditProfiles: true)
            XCTAssertEqual(
                state.editor,
                SSHProfileEditorContext(profile: profile, isNew: false)
            )
        }
    }

    func testSuccessfulSaveSelectsProfileAndClearsOperationError() async {
        await MainActor.run {
            let store = ConnectionsSettingsStoreStub()
            let controller = SSHConnectionsController(store: store) { _ in }
            let state = ConnectionsSettingsViewState()
            let profile = SSHProfile(name: "Production", host: "prod")
            state.operationError = "Old error"

            do {
                try state.save(
                    profile,
                    context: SSHProfileEditorContext(profile: profile, isNew: true),
                    using: controller
                )
            } catch {
                XCTFail("Save failed: \(error)")
            }

            XCTAssertEqual(controller.profiles, [profile])
            XCTAssertEqual(state.selectedID, profile.id)
            XCTAssertNil(state.operationError)
        }
    }

    func testSaveFailureStaysInEditorWithoutDuplicatingControllerBanner() async {
        await MainActor.run {
            let store = ConnectionsSettingsStoreStub()
            store.saveError = ConnectionsSettingsStubFailure.save
            let controller = SSHConnectionsController(store: store) { _ in }
            let state = ConnectionsSettingsViewState()
            let profile = SSHProfile(name: "Production", host: "prod")

            do {
                try state.save(
                    profile,
                    context: SSHProfileEditorContext(profile: profile, isNew: true),
                    using: controller
                )
                XCTFail("A failed store save must be surfaced to the editor")
            } catch {
                XCTAssertEqual(error as? ConnectionsSettingsStubFailure, .save)
            }

            XCTAssertNil(controller.problem)
            XCTAssertTrue(controller.profiles.isEmpty)
            XCTAssertNil(state.selectedID)
        }
    }

    func testMoveAvailabilityAndActionFollowCurrentSelection() async {
        await MainActor.run {
            let first = SSHProfile(name: "First", host: "first")
            let second = SSHProfile(name: "Second", host: "second")
            let store = ConnectionsSettingsStoreStub(profiles: [first, second])
            let controller = SSHConnectionsController(store: store) { _ in }
            let state = ConnectionsSettingsViewState()
            state.selectedID = second.id

            XCTAssertTrue(state.canMoveSelected(in: controller.profiles, by: -1))
            XCTAssertFalse(state.canMoveSelected(in: controller.profiles, by: 1))

            state.moveSelected(using: controller, by: -1)

            XCTAssertEqual(controller.profiles.map(\.id), [second.id, first.id])
            XCTAssertEqual(state.selectedID, second.id)
            XCTAssertNil(state.operationError)
        }
    }

    func testFailedRemovalClearsConfirmationAndShowsOperationError() async {
        await MainActor.run {
            let controller = SSHConnectionsController(
                store: ConnectionsSettingsStoreStub()
            ) { _ in }
            let state = ConnectionsSettingsViewState()
            let missing = SSHProfile(name: "Missing", host: "missing")
            state.requestDeletion(of: missing)

            state.remove(missing, using: controller)

            XCTAssertNil(state.pendingDeletion)
            XCTAssertEqual(
                state.operationError,
                SSHConnectionsControllerError.profileNotFound(missing.id).localizedDescription
            )
        }
    }
}

private enum ConnectionsSettingsStubFailure: Error, Equatable, LocalizedError {
    case save

    var errorDescription: String? { "The disk is full." }
}

private final class ConnectionsSettingsStoreStub: SSHProfileStoring {
    var profiles: [SSHProfile]
    var saveError: Error?

    init(profiles: [SSHProfile] = []) {
        self.profiles = profiles
    }

    func load() throws -> [SSHProfile] {
        profiles
    }

    func save(_ profiles: [SSHProfile]) throws {
        if let saveError { throw saveError }
        self.profiles = profiles
    }
}
