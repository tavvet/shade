import XCTest
@testable import Shade

@MainActor
final class SSHConnectionRequestTests: XCTestCase {
    func testQuickSlotWaitsForPendingReloadAndUsesRefreshedOrderAndHost() async {
        let fixture = Fixture()
        await fixture.controller.reload()
        fixture.store.suspendNextLoad = true
        let openingReload = Task { await fixture.controller.reload() }
        await fixture.store.waitForLoad()

        let request = fixture.requests.connect(.quickSlot(1)) { fixture.didConnect() }
        XCTAssertTrue(fixture.controller.isLoading)
        XCTAssertTrue(fixture.connected.isEmpty)

        var updated = fixture.second
        updated.host = "updated.example"
        fixture.store.finishLoad(with: .success([updated, fixture.first]))
        await openingReload.value
        await request.value

        XCTAssertEqual(fixture.connected, [updated])
        XCTAssertEqual(fixture.completedCount, 1)
    }

    func testRequestIsDroppedWhenNoLongerWantedAfterRefresh() async {
        let fixture = Fixture()
        await fixture.controller.reload()
        fixture.store.suspendNextLoad = true
        let wanted = Flag()

        let request = fixture.requests.connect(
            .quickSlot(1),
            onConnected: { fixture.didConnect() },
            onlyIf: { wanted.value }
        )
        await fixture.store.waitForLoad()
        wanted.value = false  // e.g. the panel disappeared during the refresh
        fixture.store.finishLoad(with: .success([fixture.first, fixture.second]))
        await request.value

        XCTAssertTrue(fixture.connected.isEmpty)
        XCTAssertEqual(fixture.completedCount, 0)
    }

    func testCompletionIsOptional() async {
        let fixture = Fixture()

        await fixture.requests.connect(.quickSlot(2)).value

        XCTAssertEqual(fixture.connected, [fixture.second])
    }

    func testProfileRequestRefreshesLibraryAndKeepsSelectedIdentity() async {
        let fixture = Fixture()
        await fixture.controller.reload()
        fixture.store.suspendNextLoad = true

        let request = fixture.requests.connect(.profile(fixture.first.id)) { fixture.didConnect() }
        await fixture.store.waitForLoad()
        XCTAssertTrue(fixture.connected.isEmpty)

        var updated = fixture.first
        updated.host = "updated.example"
        fixture.store.finishLoad(with: .success([fixture.second, updated]))
        await request.value

        XCTAssertEqual(fixture.connected, [updated])
        XCTAssertEqual(fixture.completedCount, 1)
    }

    func testDismissalCancelsConnectionWithoutCancellingSharedReload() async {
        let fixture = Fixture()
        await fixture.controller.reload()
        fixture.store.suspendNextLoad = true

        let request = fixture.requests.connect(.quickSlot(1)) { fixture.didConnect() }
        await fixture.store.waitForLoad()
        fixture.requests.cancel()
        fixture.store.finishLoad(with: .success([fixture.second]))
        await request.value

        XCTAssertTrue(fixture.connected.isEmpty)
        XCTAssertEqual(fixture.completedCount, 0)
        XCTAssertEqual(fixture.controller.profiles, [fixture.second])
    }

    func testLatestRequestReplacesPendingConnection() async {
        let fixture = Fixture()
        await fixture.controller.reload()
        fixture.store.suspendNextLoad = true

        let firstRequest = fixture.requests.connect(.quickSlot(1)) { fixture.didConnect() }
        await fixture.store.waitForLoad()
        let latestRequest = fixture.requests.connect(.quickSlot(2)) { fixture.didConnect() }
        fixture.store.finishLoad(with: .success([fixture.first, fixture.second]))
        await firstRequest.value
        await latestRequest.value

        XCTAssertEqual(fixture.connected, [fixture.second])
        XCTAssertEqual(fixture.completedCount, 1)
    }

    func testReopenedPickerCanRequestConnectionAfterPreviousRequestWasCancelled() async {
        let fixture = Fixture()
        await fixture.controller.reload()
        fixture.store.suspendNextLoad = true

        let oldRequest = fixture.requests.connect(.quickSlot(1)) { fixture.didConnect() }
        await fixture.store.waitForLoad()
        fixture.requests.cancel()
        let newRequest = fixture.requests.connect(.profile(fixture.second.id)) { fixture.didConnect() }
        fixture.store.finishLoad(with: .success([fixture.first, fixture.second]))
        await oldRequest.value
        await newRequest.value

        XCTAssertEqual(fixture.connected, [fixture.second])
        XCTAssertEqual(fixture.completedCount, 1)
    }

    func testFailedReloadAllowsCachedConnectionOnlyAfterFailure() async {
        let fixture = Fixture()
        await fixture.controller.reload()
        fixture.store.suspendNextLoad = true

        let request = fixture.requests.connect(.quickSlot(1)) { fixture.didConnect() }
        await fixture.store.waitForLoad()
        XCTAssertTrue(fixture.connected.isEmpty)
        fixture.store.finishLoad(with: .failure(TestFailure.load))
        await request.value

        XCTAssertEqual(fixture.connected, [fixture.first])
        XCTAssertEqual(fixture.completedCount, 1)
        XCTAssertEqual(fixture.controller.problem?.kind, .load)
    }

    func testRemovedSelectionDoesNotConnectOrDismissAfterReload() async {
        let fixture = Fixture()
        await fixture.controller.reload()
        fixture.store.suspendNextLoad = true

        let request = fixture.requests.connect(.profile(fixture.first.id)) { fixture.didConnect() }
        await fixture.store.waitForLoad()
        fixture.store.finishLoad(with: .success([fixture.second]))
        await request.value

        XCTAssertTrue(fixture.connected.isEmpty)
        XCTAssertEqual(fixture.completedCount, 0)
        XCTAssertEqual(fixture.controller.problem?.kind, .connection)
    }
}

@MainActor
private final class Fixture {
    let first = SSHProfile(name: "First", host: "first.example")
    let second = SSHProfile(name: "Second", host: "second.example")
    lazy var store = SuspendedProfileStore(profiles: [first, second])
    lazy var controller = SSHConnectionsController(store: store) { [unowned self] in
        connected.append($0)
    }
    lazy var requests = SSHConnectionRequest(controller: controller)
    var connected: [SSHProfile] = []
    var completedCount = 0

    func didConnect() { completedCount += 1 }
}

private enum TestFailure: Error { case load }

@MainActor
private final class Flag {
    var value = true
}

@MainActor
private final class SuspendedProfileStore: SSHProfileStoring {
    var profiles: [SSHProfile]
    var suspendNextLoad = false
    private var pendingLoad: CheckedContinuation<[SSHProfile], any Error>?
    private var loadWaiter: CheckedContinuation<Void, Never>?

    init(profiles: [SSHProfile]) { self.profiles = profiles }

    func load() async throws -> [SSHProfile] {
        guard suspendNextLoad else { return profiles }
        suspendNextLoad = false
        return try await withCheckedThrowingContinuation { continuation in
            pendingLoad = continuation
            loadWaiter?.resume()
            loadWaiter = nil
        }
    }

    func waitForLoad() async {
        guard pendingLoad == nil else { return }
        await withCheckedContinuation { loadWaiter = $0 }
    }

    func finishLoad(with result: Result<[SSHProfile], any Error>) {
        if case .success(let profiles) = result { self.profiles = profiles }
        let continuation = pendingLoad
        pendingLoad = nil
        continuation?.resume(with: result)
    }

    func save(_ profiles: [SSHProfile]) async throws { self.profiles = profiles }
}
