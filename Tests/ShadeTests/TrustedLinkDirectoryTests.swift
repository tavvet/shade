import AppKit
import XCTest
@testable import SwiftTerm
@testable import Shade

final class TrustedLinkDirectoryTests: XCTestCase {
    private let local = TrustedLinkDirectory.State(running: true, pid: 10, foregroundGroup: 10)
    private let shell = TrustedLinkDirectory.ShellIdentity(
        path: "/bin/zsh", group: 10, startedSeconds: 100, startedMicroseconds: 0)

    func testReadsFreshCwdOnEveryActivation() {
        var directory = "/first"
        let read = { TrustedLinkDirectory.read(state: { self.local }, inspect: { _ in self.shell }, cwd: { _ in directory }) }
        XCTAssertEqual(read(), "/first")
        directory = "/second"
        XCTAssertEqual(read(), "/second")
    }

    func testMissingLifecycleOrForegroundGroupNeverReadsCwd() {
        for state in [TrustedLinkDirectory.State(running: false, pid: 10, foregroundGroup: 10),
                      .init(running: true, pid: 0, foregroundGroup: 10),
                      .init(running: true, pid: 10, foregroundGroup: nil),
                      .init(running: true, pid: 10, foregroundGroup: 20)] {
            XCTAssertNil(TrustedLinkDirectory.read(state: { state }, inspect: { _ in self.shell }, cwd: { _ in
                XCTFail("Untrusted lifecycle must not read cwd"); return "/wrong"
            }))
        }
    }

    func testMissingMetadataAndUnreadableOrInvalidCwdFailClosed() {
        XCTAssertNil(TrustedLinkDirectory.read(state: { local }, inspect: { _ in nil }, cwd: { _ in "/wrong" }))
        for directory in [nil, "", "relative", "/bad\0path"] as [String?] {
            XCTAssertNil(TrustedLinkDirectory.read(state: { local }, inspect: { _ in shell }, cwd: { _ in directory }))
        }
    }

    func testExitAndRestartNeverReuseOldDirectory() {
        var state = local
        let read = { TrustedLinkDirectory.read(state: { state }, inspect: { _ in self.shell }, cwd: { _ in "/old" }) }
        XCTAssertEqual(read(), "/old")
        state.running = false
        XCTAssertNil(read())
        state = .init(running: true, pid: 20, foregroundGroup: 20)
        XCTAssertNil(read()) // Old process metadata cannot qualify the new PID.
        var replacement = shell
        replacement.group = 20
        XCTAssertEqual(TrustedLinkDirectory.read(state: { state }, inspect: { _ in replacement }, cwd: { _ in "/new" }), "/new")
    }

    func testProcessIdentityOrLifecycleChangeDuringReadFailsClosed() {
        var identity = shell
        XCTAssertNil(TrustedLinkDirectory.read(state: { local }, inspect: { _ in identity }, cwd: { _ in
            identity.startedSeconds += 1 // Same PID reused by a different process.
            return "/stale"
        }))
        var state = local
        XCTAssertNil(TrustedLinkDirectory.read(state: { state }, inspect: { _ in shell }, cwd: { _ in
            state.running = false
            return "/stale"
        }))
    }

    func testLocalShellRequiresCompletePositiveInspection() {
        XCTAssertEqual(ProcessTree.idleLocalShell(10, metadata: { _ in shell }, children: { _ in [] }), shell)
        XCTAssertNil(ProcessTree.idleLocalShell(10, metadata: { _ in nil }, children: { _ in [] }))
        XCTAssertNil(ProcessTree.idleLocalShell(10, metadata: { _ in shell }, children: { _ in nil }))
        var unknownGroup = shell
        unknownGroup.group = 0
        XCTAssertNil(ProcessTree.idleLocalShell(10, metadata: { _ in unknownGroup }, children: { _ in [] }))
        for path in ["/usr/bin/ssh", "/usr/local/bin/zsh", "/usr/bin/tmux", ""] {
            var remote = shell
            remote.path = path
            XCTAssertNil(ProcessTree.idleLocalShell(10, metadata: { _ in remote }, children: { _ in [] }))
        }
    }

    func testRemoteForegroundWrapperFailsButVerifiedBackgroundSSHDoesNot() {
        var ssh = shell
        ssh.path = "/usr/bin/ssh"
        let children: (Int32) -> [Int32]? = { $0 == 10 ? [20] : [] }
        XCTAssertNil(ProcessTree.idleLocalShell(10, metadata: { $0 == 10 ? self.shell : ssh }, children: children))
        ssh.group = 20
        XCTAssertNotNil(ProcessTree.idleLocalShell(10, metadata: { $0 == 10 ? self.shell : ssh }, children: children))
        XCTAssertNil(ProcessTree.idleLocalShell(10, metadata: { $0 == 10 ? self.shell : nil }, children: children))
        XCTAssertNil(ProcessTree.idleLocalShell(10, metadata: { $0 == 10 ? self.shell : ssh }, children: { $0 == 10 ? [20] : nil }))
    }

    func testNestedForegroundChildAndCyclesFailClosed() {
        var background = shell
        background.group = 20
        XCTAssertNil(ProcessTree.idleLocalShell(10, metadata: { $0 == 20 ? background : self.shell },
                                              children: { $0 == 10 ? [20] : ($0 == 20 ? [30] : []) }))
        XCTAssertNil(ProcessTree.idleLocalShell(10, metadata: { $0 == 10 ? self.shell : background },
                                              children: { $0 == 10 ? [20] : [10] }))
    }

    func testBackgroundMetadataChangesInvalidateRead() {
        var background = shell
        background.group = 20
        background.path = "/usr/bin/ssh"
        let inspect: (Int32) -> TrustedLinkDirectory.ShellIdentity? = { pid in
            ProcessTree.idleLocalShell(pid, metadata: { $0 == 10 ? self.shell : background },
                                      children: { $0 == 10 ? [20] : [] })
        }
        XCTAssertNil(TrustedLinkDirectory.read(state: { local }, inspect: inspect, cwd: { _ in
            background.startedSeconds += 1
            return "/changed"
        }))
        background.group = 0
        XCTAssertNil(inspect(10))
    }

    func testChildSnapshotDistinguishesEmptySuccessFromZeroByteFailure() {
        errno = EACCES // Stale errno must be cleared before a successful call.
        XCTAssertEqual(ProcessTree.inspectedChildren(10, list: { _, _, _ in
            XCTAssertEqual(errno, 0)
            return 0
        }), [])
        for error in [EACCES, ESRCH, EPERM] {
            XCTAssertNil(ProcessTree.inspectedChildren(10, list: { _, _, _ in
                errno = error
                return 0
            }))
        }
    }

    func testChildSnapshotRejectsInvalidLengthsAndRetainsKnownChildren() {
        for bytes in [-1, 1, 256, 260] as [Int32] {
            XCTAssertNil(ProcessTree.inspectedChildren(10, list: { _, _, _ in bytes }))
        }
        XCTAssertEqual(ProcessTree.inspectedChildren(10, list: { _, buffer, _ in
            buffer.storeBytes(of: pid_t(20), as: pid_t.self)
            return Int32(MemoryLayout<pid_t>.stride)
        }), [20])
    }
}

@MainActor
final class TrustedLinkDirectoryIntegrationTests: XCTestCase {
    func testProviderTracksLiveShellCwdThenClearsOnExitAndRestart() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let first = root.appendingPathComponent("first")
        let second = root.appendingPathComponent("second")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // Identical basenames must resolve in the current shell directory,
        // never an OSC 7/UI cache or the assistant/application's working folder.
        try Data("first".utf8).write(to: first.appendingPathComponent("same.txt"))
        try Data("second".utf8).write(to: second.appendingPathComponent("same.txt"))
        let controller = TerminalProcessController(shellPath: "/bin/sh")
        let view = controller.view
        var opened: [String] = []
        var blockedAlerts = 0
        controller.onOpenLink = { opened.append($0) }
        let activate = {
            view.activateLink("same.txt", params: [:], isExplicit: false, presentAlert: { alert, _, completion in
                XCTAssertEqual(alert.messageText, "Link blocked")
                blockedAlerts += 1
                completion(.alertFirstButtonReturn)
            }, open: { _ in
                XCTFail("The Shade delegate must capture the checked URL without launching an application")
            })
        }
        defer { view.process.terminate() }
        let provider = try XCTUnwrap(view.linkFallbackDirectoryProvider)
        XCTAssertNil(provider())
        let environment = ["PATH=/usr/bin:/bin", "HOME=\(root.path)", "ENV=/dev/null",
                           "BASH_ENV=/dev/null", "TERM=xterm-256color"]
        view.startProcess(executable: "/bin/sh", args: ["-i"], environment: environment, currentDirectory: first.path)
        let firstPath = first.resolvingSymlinksInPath().path
        let secondPath = second.resolvingSymlinksInPath().path
        // Darwin may report /private/var while Foundation uses its /var alias.
        // Normalize comparisons only; the provider must return the kernel path.
        let comparablePath = { provider().map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path } }
        waitForCondition { comparablePath() == firstPath }
        XCTAssertEqual(comparablePath(), firstPath)
        activate()
        XCTAssertEqual(opened.compactMap { URL(string: $0)?.resolvingSymlinksInPath().path },
                       [first.appendingPathComponent("same.txt").resolvingSymlinksInPath().path])
        XCTAssertEqual(blockedAlerts, 0)
        controller.sendUserInput(Array("cd '\(second.path)'\n".utf8))
        waitForCondition { comparablePath() == secondPath }
        XCTAssertEqual(comparablePath(), secondPath)
        let base = try XCTUnwrap(provider())
        XCTAssertEqual(try String(contentsOfFile: base + "/same.txt", encoding: .utf8), "second")
        activate()
        XCTAssertEqual(opened.compactMap { URL(string: $0)?.resolvingSymlinksInPath().path },
                       [first.appendingPathComponent("same.txt").resolvingSymlinksInPath().path,
                        second.appendingPathComponent("same.txt").resolvingSymlinksInPath().path])
        XCTAssertEqual(blockedAlerts, 0)
        controller.sendUserInput(Array("exit\n".utf8))
        waitForCondition { !controller.isRunning && !view.process.windingDown }
        XCTAssertNil(provider())
        activate()
        waitForCondition { blockedAlerts == 1 }
        XCTAssertEqual(opened.count, 2)
        view.startProcess(executable: "/bin/sh", args: ["-i"], environment: environment, currentDirectory: first.path)
        waitForCondition { comparablePath() == firstPath }
        XCTAssertEqual(comparablePath(), firstPath)
    }
}
