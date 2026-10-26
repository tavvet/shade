import AppKit
import SwiftTerm
import XCTest
@testable import Shade
@testable import ShadeCore

@MainActor
final class PinnedTabTests: XCTestCase {
    func testPinnedTabRefusesUserCloseUntilUnpinned() {
        let controller = TerminalsController(preferences: StaticPreferences())
        let first = controller.newSession(configuration: .waitingForTermination)
        let second = controller.newSession(configuration: .waitingForTermination)
        defer { stop([first, second]) }

        controller.togglePin(at: 1)

        XCTAssertTrue(controller.sessions.elementsEqual([second, first], by: ===))
        XCTAssertTrue(controller.isPinned(at: 0))
        XCTAssertTrue(controller.activeSession === second)
        XCTAssertFalse(controller.closeActive())
        XCTAssertFalse(controller.close(at: 0))
        XCTAssertEqual(controller.sessions.count, 2)

        controller.toggleActivePin()

        XCTAssertFalse(controller.isPinned(at: 0))
        XCTAssertTrue(controller.closeActive())
        XCTAssertTrue(controller.sessions.elementsEqual([first], by: ===))
    }

    func testExitOfAPinnedTabKeepsItWhileAnUnpinnedTabCloses() {
        let controller = TerminalsController(preferences: StaticPreferences())
        let pinned = controller.newSession(configuration: .waitingForTermination)
        let plain = controller.newSession(configuration: .waitingForTermination)
        defer { stop([pinned, plain]) }
        controller.togglePin(at: 0)

        // The pinned process still runs, as after a restart that won the race
        // with this exit event, so the event is ignored and the tab stays.
        pinned.onExit?()
        plain.onExit?()

        XCTAssertTrue(controller.sessions.elementsEqual([pinned], by: ===))
    }

    func testObservableShowsPinnedTabsFirstWithTheirNewNumbers() {
        let controller = TerminalsController(preferences: StaticPreferences())
        let observable = TabsObservable(controller: controller)
        let first = controller.newSession(configuration: .waitingForTermination)
        let second = controller.newSession(configuration: .waitingForTermination)
        defer { stop([first, second]) }
        controller.renameSession(at: 1, to: "Logs")

        controller.togglePin(at: 1)

        XCTAssertEqual(observable.tabs.map(\.id), [second.id, first.id])
        XCTAssertEqual(observable.tabs.map(\.isPinned), [true, false])
        XCTAssertEqual(observable.tabs[0].label, "1 · Logs")
        XCTAssertEqual(observable.activeIndex, 0)
    }

    func testRestartStartsALoginShellInTheGivenDirectoryOnlyWhenIdle() {
        var launches: [(executable: String, arguments: [String], execName: String?, directory: String?)] = []
        let controller = TerminalProcessController(
            shellPath: "/bin/zsh",
            processStarter: { _, executable, arguments, _, execName, directory in
                launches.append((executable, arguments, execName, directory))
                return true
            },
            shellEnvironment: { _, _ in nil }
        )

        XCTAssertTrue(controller.restartLoginShell(shellEnrichment: false, directory: "/tmp"))

        XCTAssertEqual(launches.map(\.executable), ["/bin/zsh"])
        XCTAssertEqual(launches.first?.arguments, ["-l"])
        XCTAssertEqual(launches.first?.execName, "-zsh")
        XCTAssertEqual(launches.first?.directory, "/tmp")

        controller.view.startProcess(executable: "/bin/sleep", args: ["3"])
        defer { controller.view.process.terminate() }

        XCTAssertFalse(controller.restartLoginShell(shellEnrichment: false, directory: nil))
        XCTAssertEqual(launches.count, 1)
    }

    func testRestartRelaunchesInTheSameViewAfterTheProcessExits() {
        // A private HOME keeps `sh -l` away from the developer's ~/.profile.
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("shade-pinned-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let controller = TerminalProcessController(
            shellPath: "/bin/sh",
            shellEnvironment: { _, _ in
                ["HOME=\(home.path)", "PATH=/usr/bin:/bin", "TERM=xterm-256color", "ENV=/dev/null"]
            }
        )
        defer { controller.view.process.terminate() }
        var restarted: Bool?
        controller.onExit = { [weak controller] in
            restarted = controller?.restartLoginShell(shellEnrichment: false, directory: nil)
        }

        controller.view.startProcess(executable: "/bin/sh", args: ["-c", "exit 0"])
        waitForCondition { restarted != nil }

        XCTAssertEqual(restarted, true)
        XCTAssertTrue(controller.isRunning)
        XCTAssertGreaterThan(controller.shellPid, 0)
    }

    func testLaunchAfterARestartNeverRepeatsTheInitialCommand() {
        var results = [true, false, true]
        var launches: [(executable: String, arguments: [String])] = []
        let controller = TerminalProcessController(
            configuration: TerminalLaunchConfiguration(
                initialCommand: ProcessInvocation(executable: "/usr/bin/ssh", arguments: ["prod"])
            ),
            shellPath: "/bin/zsh",
            processStarter: { _, executable, arguments, _, _, _ in
                launches.append((executable, arguments))
                return results.removeFirst()
            },
            shellEnvironment: { _, _ in nil }
        )

        controller.start(shellEnrichment: false)
        // The restart's launch fails, so the next start must try again.
        XCTAssertFalse(controller.restartLoginShell(shellEnrichment: false, directory: "/tmp"))
        controller.start(shellEnrichment: false)

        XCTAssertEqual(launches.count, 3)
        XCTAssertNotEqual(launches[0].executable, "/bin/zsh")
        XCTAssertEqual(launches[1].executable, "/bin/zsh")
        XCTAssertEqual(launches[2].executable, "/bin/zsh")
        XCTAssertEqual(launches[2].arguments, ["-l"])
    }

    func testRestartLeavesTheAlternateScreenAnExitedProgramLeftOn() {
        let controller = TerminalProcessController(
            processStarter: { _, _, _, _, _, _ in true },
            shellEnvironment: { _, _ in nil }
        )
        controller.view.feed(text: "\u{1B}[?1049h\u{1B}[?25l")
        waitForCondition { controller.view.terminalInputStateSnapshot()?.isAlternateBuffer == true }

        controller.restartLoginShell(shellEnrichment: false, directory: nil)

        waitForCondition { controller.view.terminalInputStateSnapshot()?.isAlternateBuffer == false }
    }

    private func stop(_ sessions: [TerminalSession]) {
        for session in sessions {
            session.onExit = nil
            session.terminate()
        }
    }
}
