import XCTest
@testable import Shade

final class SSHConnectionsControllerTests: XCTestCase {
    func testInitializationLoadsAndNormalizesProfiles() async {
        await MainActor.run {
            let id = UUID()
            let store = SSHProfileStoreStub(
                profiles: [SSHProfile(id: id, name: " Production ", host: " prod ")]
            )
            let controller = SSHConnectionsController(store: store) { _ in }

            XCTAssertEqual(
                controller.profiles,
                [SSHProfile(id: id, name: "Production", host: "prod")]
            )
            XCTAssertNil(controller.problem)
            XCTAssertTrue(controller.canEditProfiles)
            XCTAssertEqual(store.loadCount, 1)
        }
    }

    func testLoadFailureBlocksWritesWithoutReplacingOnDiskData() async {
        await MainActor.run {
            let store = SSHProfileStoreStub()
            store.loadError = StubFailure.load
            let controller = SSHConnectionsController(store: store) { _ in }

            XCTAssertEqual(controller.problem?.kind, .load)
            XCTAssertFalse(controller.canEditProfiles)
            XCTAssertTrue(controller.profiles.isEmpty)
            controller.dismissProblem()
            XCTAssertEqual(controller.problem?.kind, .load)
            XCTAssertFalse(controller.connect(to: UUID()))
            XCTAssertEqual(controller.problem?.kind, .load)

            do {
                try controller.add(SSHProfile(name: "Production", host: "prod"))
                XCTFail("A failed library load must block writes")
            } catch {
                XCTAssertEqual(error as? SSHConnectionsControllerError, .libraryUnavailable)
            }
            XCTAssertTrue(store.saveAttempts.isEmpty)
        }
    }

    func testReloadRecoversAfterExternalFileRepair() async {
        await MainActor.run {
            let store = SSHProfileStoreStub()
            store.loadError = StubFailure.load
            let controller = SSHConnectionsController(store: store) { _ in }
            let repaired = SSHProfile(name: "Production", host: "prod")

            store.loadError = nil
            store.profiles = [repaired]
            controller.reload()

            XCTAssertEqual(controller.profiles, [repaired])
            XCTAssertNil(controller.problem)
            XCTAssertTrue(controller.canEditProfiles)
            XCTAssertEqual(store.loadCount, 2)
        }
    }

    func testAddUpdateMoveAndRemovePersistBeforePublishing() async {
        await MainActor.run {
            let first = SSHProfile(name: "Production", host: "prod")
            var second = SSHProfile(name: "Staging", host: "stage")
            let store = SSHProfileStoreStub(profiles: [first])
            let controller = SSHConnectionsController(store: store) { _ in }

            do {
                _ = try controller.add(second)
                second.name = "QA"
                try controller.update(second)
                try controller.move(id: second.id, to: 0)
                try controller.remove(id: first.id)
            } catch {
                XCTFail("CRUD sequence failed: \(error)")
            }

            XCTAssertEqual(controller.profiles, [second])
            XCTAssertEqual(store.profiles, [second])
            XCTAssertEqual(store.saveAttempts.count, 4)
        }
    }

    func testDuplicateNameLeavesPublishedAndPersistedStateUntouched() async {
        await MainActor.run {
            let existing = SSHProfile(name: "Production", host: "prod-a")
            let store = SSHProfileStoreStub(profiles: [existing])
            let controller = SSHConnectionsController(store: store) { _ in }

            do {
                try controller.add(SSHProfile(name: "production", host: "prod-b"))
                XCTFail("Duplicate names must be rejected")
            } catch {
                XCTAssertEqual(error as? SSHProfileStoreError, .duplicateName("production"))
            }

            XCTAssertEqual(controller.profiles, [existing])
            XCTAssertEqual(store.profiles, [existing])
            XCTAssertTrue(store.saveAttempts.isEmpty)
        }
    }

    func testSaveFailureDoesNotPublishCandidateAndCanBeRetried() async {
        await MainActor.run {
            let existing = SSHProfile(name: "Production", host: "prod")
            let added = SSHProfile(name: "Staging", host: "stage")
            let store = SSHProfileStoreStub(profiles: [existing])
            store.saveError = StubFailure.save
            let controller = SSHConnectionsController(store: store) { _ in }

            do {
                try controller.add(added)
                XCTFail("A failed save must not publish the candidate")
            } catch {
                XCTAssertEqual(error as? StubFailure, .save)
            }
            XCTAssertEqual(controller.profiles, [existing])
            XCTAssertEqual(store.profiles, [existing])
            XCTAssertEqual(controller.problem?.kind, .save)

            controller.dismissProblem()
            store.saveError = nil
            do {
                _ = try controller.add(added)
            } catch {
                XCTFail("Retry after storage recovery failed: \(error)")
            }
            XCTAssertEqual(controller.profiles, [existing, added])
            XCTAssertNil(controller.problem)
        }
    }

    func testMoveClampsToFirstAndLastStableSlot() async {
        await MainActor.run {
            let first = SSHProfile(name: "First", host: "first")
            let second = SSHProfile(name: "Second", host: "second")
            let third = SSHProfile(name: "Third", host: "third")
            let store = SSHProfileStoreStub(profiles: [first, second, third])
            let controller = SSHConnectionsController(store: store) { _ in }

            do {
                try controller.move(id: first.id, to: 99)
            } catch {
                XCTFail("Move to last slot failed: \(error)")
            }
            XCTAssertEqual(controller.profiles.map(\.id), [second.id, third.id, first.id])

            do {
                try controller.move(id: first.id, to: -10)
            } catch {
                XCTFail("Move to first slot failed: \(error)")
            }
            XCTAssertEqual(controller.profiles.map(\.id), [first.id, second.id, third.id])
        }
    }

    func testSuccessfulConnectionClosesPicker() async {
        await MainActor.run {
            let profile = SSHProfile(name: "Production", host: "prod")
            let store = SSHProfileStoreStub(profiles: [profile])
            var connectedIDs: [UUID] = []
            let controller = SSHConnectionsController(store: store) {
                connectedIDs.append($0.id)
            }
            controller.presentPicker()

            XCTAssertTrue(controller.connect(to: profile.id))
            XCTAssertEqual(connectedIDs, [profile.id])
            XCTAssertFalse(controller.isPickerPresented)
            XCTAssertNil(controller.problem)
        }
    }

    func testFailedConnectionKeepsPickerOpenAndReportsProblem() async {
        await MainActor.run {
            let profile = SSHProfile(name: "Production", host: "prod")
            let store = SSHProfileStoreStub(profiles: [profile])
            let controller = SSHConnectionsController(store: store) { _ in
                throw StubFailure.connection
            }
            controller.presentPicker()

            XCTAssertFalse(controller.connect(to: profile.id))
            XCTAssertTrue(controller.isPickerPresented)
            XCTAssertEqual(controller.problem?.kind, .connection)
        }
    }

    func testQuickSlotsAreOneBasedAndFollowProfileOrder() async {
        await MainActor.run {
            let first = SSHProfile(name: "First", host: "first")
            let second = SSHProfile(name: "Second", host: "second")
            let store = SSHProfileStoreStub(profiles: [first, second])
            var connectedIDs: [UUID] = []
            let controller = SSHConnectionsController(store: store) {
                connectedIDs.append($0.id)
            }

            XCTAssertFalse(controller.connectQuickSlot(0))
            XCTAssertTrue(controller.connectQuickSlot(2))
            XCTAssertFalse(controller.connectQuickSlot(3))
            XCTAssertEqual(connectedIDs, [second.id])
        }
    }
}

private enum StubFailure: Error {
    case load
    case save
    case connection
}

private final class SSHProfileStoreStub: SSHProfileStoring {
    var profiles: [SSHProfile]
    var loadError: Error?
    var saveError: Error?
    private(set) var loadCount = 0
    private(set) var saveAttempts: [[SSHProfile]] = []

    init(profiles: [SSHProfile] = []) {
        self.profiles = profiles
    }

    func load() throws -> [SSHProfile] {
        loadCount += 1
        if let loadError { throw loadError }
        return profiles
    }

    func save(_ profiles: [SSHProfile]) throws {
        saveAttempts.append(profiles)
        if let saveError { throw saveError }
        self.profiles = profiles
    }
}
