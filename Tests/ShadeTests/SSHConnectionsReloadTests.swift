import Combine
import XCTest
@testable import Shade

@MainActor
final class SSHConnectionsReloadTests: XCTestCase {
    func testLocationChangeDiscardsOldLoadAndKeepsAllCallersWaitingForNewLibrary() async throws {
        let cached = SSHProfile(name: "Cached", host: "cached")
        let old = SSHProfile(name: "Portable", host: "portable")
        let local = SSHProfile(name: "Local", host: "local")
        let store = SuspendedReloadStore(profiles: [cached])
        let controller = SSHConnectionsController(store: store) { _ in }
        await controller.reload()
        var published: [[SSHProfile]] = []
        let observation = controller.$profiles.dropFirst().sink { published.append($0) }
        defer { observation.cancel() }

        let oldStarted = expectation(description: "Old backend read started")
        store.onLoad = { oldStarted.fulfill() }
        let oldReload = Task { await controller.reload() }
        await fulfillment(of: [oldStarted], timeout: 2)

        controller.invalidateLibrary()
        let newStarted = expectation(description: "New backend read started")
        store.onLoad = { newStarted.fulfill() }
        var freshReloadFinished = false
        let freshReload = Task { await controller.reload(); freshReloadFinished = true }
        store.completeLoad(.success([old]))
        await fulfillment(of: [newStarted], timeout: 2)

        XCTAssertFalse(freshReloadFinished)
        XCTAssertTrue(controller.isLoading)
        XCTAssertFalse(controller.canEditProfiles)
        XCTAssertEqual(controller.profiles, [cached])
        XCTAssertTrue(published.isEmpty)
        XCTAssertFalse(controller.connectQuickSlot(1))
        await assertThrowsAsync { try await controller.add(SSHProfile(name: "Added", host: "added")) }
        XCTAssertEqual(store.saveCount, 0)

        store.completeLoad(.success([local]))
        await oldReload.value
        await freshReload.value
        XCTAssertEqual(controller.profiles, [local])
        XCTAssertEqual(published, [[local]])
        XCTAssertTrue(controller.canEditProfiles)
        XCTAssertFalse(controller.isLoading)
        XCTAssertEqual(store.loadCount, 3)
        let added = SSHProfile(name: "Added", host: "added")
        try await controller.add(added)
        XCTAssertEqual(store.profiles, [local, added])
    }

    func testLocationChangeRetriesOldFailureWithoutPublishingIt() async {
        let store = SuspendedReloadStore(profiles: [])
        let controller = SSHConnectionsController(store: store) { _ in }
        let oldStarted = expectation(description: "Old read started")
        store.onLoad = { oldStarted.fulfill() }
        let reload = Task { await controller.reload() }
        await fulfillment(of: [oldStarted], timeout: 2)
        controller.invalidateLibrary()
        let newStarted = expectation(description: "New read started")
        store.onLoad = { newStarted.fulfill() }
        store.completeLoad(.failure(CocoaError(.fileReadNoSuchFile)))
        await fulfillment(of: [newStarted], timeout: 2)

        XCTAssertNil(controller.problem)
        XCTAssertFalse(controller.canEditProfiles)
        store.completeLoad(.success([]))
        await reload.value
        XCTAssertNil(controller.problem)
        XCTAssertTrue(controller.canEditProfiles)
    }

    func testInvalidationImmediatelyBlocksActionsUntilReloadAttemptFinishes() async {
        let cached = SSHProfile(name: "Cached", host: "cached")
        let store = SuspendedReloadStore(profiles: [cached])
        var connected: [SSHProfile] = []
        let controller = SSHConnectionsController(store: store) { connected.append($0) }
        XCTAssertFalse(controller.canConnectProfiles)
        await controller.reload()
        XCTAssertTrue(controller.canConnectProfiles)

        controller.invalidateLibrary()

        XCTAssertFalse(controller.canEditProfiles)
        XCTAssertFalse(controller.canConnectProfiles)
        XCTAssertFalse(controller.connectQuickSlot(1))
        let started = expectation(description: "New read started")
        store.onLoad = { started.fulfill() }
        let reload = Task { await controller.reload() }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertFalse(controller.canConnectProfiles)
        XCTAssertFalse(controller.connectQuickSlot(1))
        store.completeLoad(.failure(CocoaError(.fileReadNoSuchFile)))
        await reload.value

        // An unavailable file still permits explicitly using the cached list,
        // but only after the new backend's refresh has actually failed.
        XCTAssertFalse(controller.canEditProfiles)
        XCTAssertTrue(controller.canConnectProfiles)
        XCTAssertTrue(controller.connectQuickSlot(1))
        XCTAssertEqual(connected, [cached])
    }
}

@MainActor
private final class SuspendedReloadStore: SSHProfileStoring {
    var profiles: [SSHProfile]
    var onLoad: (() -> Void)?
    private var continuation: CheckedContinuation<[SSHProfile], Error>?
    private(set) var loadCount = 0
    private(set) var saveCount = 0

    init(profiles: [SSHProfile]) { self.profiles = profiles }

    func load() async throws -> [SSHProfile] {
        loadCount += 1
        guard let onLoad else { return profiles }
        return try await withCheckedThrowingContinuation {
            continuation = $0
            onLoad()
        }
    }

    func completeLoad(_ result: Result<[SSHProfile], Error>) {
        let pending = continuation
        continuation = nil
        if case .success(let profiles) = result { self.profiles = profiles }
        pending?.resume(with: result)
    }

    func save(_ profiles: [SSHProfile]) async throws {
        saveCount += 1
        self.profiles = profiles
    }
}
