import AppKit
import SwiftTerm
import XCTest
@testable import Shade

@MainActor
final class TerminalProcessTerminationTests: XCTestCase {
    func testTerminatingWhileExitedOutputDrainsNeverSignalsZeroPID() {
        var signalled: [Int32] = []
        let controller = TerminalProcessController(signalSender: { pid, _ in
            signalled.append(pid)
            return 0
        })
        let view = controller.view
        view.process.drainTimeout = 3
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        view.setProcessOutputHandler {
            entered.signal()
            _ = release.wait(timeout: .now() + 5)
        }
        defer { release.signal() }
        view.startProcess(executable: "/bin/sh", args: ["-c", "printf probe"])
        XCTAssertEqual(entered.wait(timeout: .now() + 2), .success)
        waitForCondition { controller.shellPid == 0 }
        XCTAssertTrue(controller.isRunning)

        controller.terminate()

        XCTAssertTrue(signalled.isEmpty)
    }

    func testTerminatingRunningShellSignalsItsOwnProcessGroup() {
        var signals: [(pid: Int32, signal: Int32)] = []
        let controller = TerminalProcessController(signalSender: { pid, signal in
            signals.append((pid, signal))
            return 0
        })
        let view = controller.view
        view.startProcess(executable: "/bin/sleep", args: ["3"])
        defer { view.process.terminate() }
        let pid = controller.shellPid
        XCTAssertGreaterThan(pid, 0)
        // forkpty can return to the parent before the child creates its group.
        waitForCondition { getpgid(pid) == pid }
        XCTAssertEqual(getpgid(pid), pid)

        controller.terminate()

        XCTAssertEqual(signals.map(\.pid), [-pid])
        XCTAssertEqual(signals.map(\.signal), [SIGTERM])
    }

    func testFailedGroupSignalFallsBackToThePositiveShellPID() {
        var signalled: [Int32] = []
        let controller = TerminalProcessController(signalSender: { pid, _ in
            signalled.append(pid)
            return pid < 0 ? -1 : 0
        })
        let view = controller.view
        view.startProcess(executable: "/bin/sleep", args: ["3"])
        defer { view.process.terminate() }
        let pid = controller.shellPid
        XCTAssertGreaterThan(pid, 0)
        waitForCondition { getpgid(pid) == pid }

        controller.terminate()

        XCTAssertEqual(signalled, [-pid, pid])
        XCTAssertFalse(signalled.contains(0))
    }
}
