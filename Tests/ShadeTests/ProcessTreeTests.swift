import XCTest
@testable import Shade

final class ProcessTreeTests: XCTestCase {
    func testIgnoresRemoteClientInBackgroundProcessGroup() {
        let indicator = ProcessTree.remoteIndicator(
            forShell: 10,
            foregroundProcessGroup: 30,
            children: { pid in pid == 10 ? [20, 30] : [] },
            processName: { pid in pid == 20 ? "ssh" : "sleep" },
            processGroup: { pid in pid }
        )

        XCTAssertNil(indicator)
    }

    func testFindsRemoteClientInForegroundProcessGroup() {
        let indicator = ProcessTree.remoteIndicator(
            forShell: 10,
            foregroundProcessGroup: 20,
            children: { pid in pid == 10 ? [20, 30] : [] },
            processName: { pid in pid == 20 ? "ssh" : "sleep" },
            processGroup: { pid in pid }
        )

        XCTAssertEqual(indicator, "ssh")
    }

    func testFindsRemoteClientWhenItOwnsThePTY() {
        var didScanChildren = false
        let indicator = ProcessTree.remoteIndicator(
            forShell: 10,
            foregroundProcessGroup: 10,
            children: { _ in didScanChildren = true; return [] },
            processName: { pid in pid == 10 ? "ssh" : nil },
            processGroup: { pid in pid == 10 ? 10 : nil }
        )

        XCTAssertEqual(indicator, "ssh")
        XCTAssertFalse(didScanChildren)
    }

    func testFindsRemoteClientBesideForegroundWrapper() {
        let indicator = ProcessTree.remoteIndicator(
            forShell: 10,
            foregroundProcessGroup: 10,
            children: { pid in pid == 10 ? [20] : [] },
            processName: { pid in pid == 10 ? "sh" : "ssh" },
            processGroup: { _ in 10 }
        )

        XCTAssertEqual(indicator, "ssh")
    }

    func testForegroundLocalOwnerIgnoresRemoteBackgroundGroup() {
        var didScan = false
        let indicator = ProcessTree.remoteIndicator(
            forShell: 10,
            foregroundProcessGroup: 10,
            children: { _ in didScan = true; return [20] },
            processName: { pid in pid == 10 ? "zsh" : "ssh" },
            processGroup: { _ in 20 }
        )

        XCTAssertNil(indicator)
        XCTAssertTrue(didScan)
    }
}
