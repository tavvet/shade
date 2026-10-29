import AppKit
import XCTest
@testable import Shade
@testable import ShadeCore

final class QuitWarningTests: XCTestCase {
    private let tabs = [
        QuitWarning.Tab(label: "1 · Logs", isPinned: true, program: nil),
        QuitWarning.Tab(label: "2 · ~", isPinned: false, program: nil),
        QuitWarning.Tab(label: "3 · ~/src", isPinned: false, program: "vim"),
        QuitWarning.Tab(label: "4 · [ssh]", isPinned: true, program: "ssh"),
    ]

    func testEachSettingSelectsItsTabsInOrder() {
        XCTAssertEqual(QuitWarning.tabs(tabs, for: .never), [])
        XCTAssertEqual(QuitWarning.tabs(tabs, for: .pinnedTabs).map(\.label), ["1 · Logs", "4 · [ssh]"])
        XCTAssertEqual(
            QuitWarning.tabs(tabs, for: .pinnedOrBusyTabs).map(\.label),
            ["1 · Logs", "3 · ~/src", "4 · [ssh]"]
        )
    }

    func testMessageListsWhyEachTabIsMentioned() {
        XCTAssertEqual(
            QuitWarning.message(for: QuitWarning.tabs(tabs, for: .pinnedOrBusyTabs)),
            """
            Quitting closes these tabs and ends their processes:
            • 1 · Logs — pinned
            • 3 · ~/src — running vim
            • 4 · [ssh] — pinned, running ssh
            """
        )
    }
}

@MainActor
final class QuitConfirmationTests: XCTestCase {
    func testQuitAsksOnlyWhilePinnedTabsExistAndStopsWhenRefused() throws {
        let fixture = try ConfigurationFixture()
        defer { fixture.cleanup() }
        let delegate = AppDelegate(configuration: fixture.store())
        let first = delegate.terminals.newSession(configuration: .waitingForTermination)
        let second = delegate.terminals.newSession(configuration: .waitingForTermination)
        defer { stop([first, second]) }
        var asked: [QuitWarning.Tab]?
        delegate.confirmQuit = { asked = $0; return false }

        XCTAssertTrue(delegate.shouldQuit(during: nil))
        XCTAssertNil(asked)

        delegate.terminals.togglePin(at: 1)

        XCTAssertFalse(delegate.shouldQuit(during: nil))
        XCTAssertEqual(asked?.count, 1)
        XCTAssertEqual(asked?.first?.isPinned, true)
        XCTAssertEqual(delegate.applicationShouldTerminate(NSApplication.shared), .terminateCancel)

        delegate.confirmQuit = { _ in true }
        XCTAssertTrue(delegate.shouldQuit(during: nil))
    }

    func testBusySettingAsksAboutARunningProgram() throws {
        let fixture = try ConfigurationFixture()
        defer { fixture.cleanup() }
        fixture.defaults.set("pinnedOrBusyTabs", forKey: PreferencesStore.Key.quitConfirmation)
        let delegate = AppDelegate(configuration: fixture.store())
        // The command wrapper runs `sleep` in its own process group.
        let session = delegate.terminals.newSession(configuration: .waitingForTermination)
        defer { stop([session]) }
        waitForCondition { session.foregroundProgram == "sleep" }
        var asked: [QuitWarning.Tab]?
        delegate.confirmQuit = { asked = $0; return false }

        XCTAssertFalse(delegate.shouldQuit(during: nil))
        XCTAssertEqual(asked?.map(\.program), ["sleep"])
    }

    func testNeverSettingAndSystemLogoutQuitWithoutAsking() throws {
        let fixture = try ConfigurationFixture()
        defer { fixture.cleanup() }
        let delegate = AppDelegate(configuration: fixture.store())
        let session = delegate.terminals.newSession(configuration: .waitingForTermination)
        defer { stop([session]) }
        delegate.terminals.togglePin(at: 0)
        var askCount = 0
        delegate.confirmQuit = { _ in askCount += 1; return false }

        XCTAssertTrue(delegate.shouldQuit(during: quitEvent(reason: 0x6C6F_676F))) // 'logo'
        XCTAssertEqual(askCount, 0)
        XCTAssertFalse(delegate.shouldQuit(during: quitEvent(reason: nil)))
        XCTAssertEqual(askCount, 1)

        let never = try ConfigurationFixture()
        defer { never.cleanup() }
        never.defaults.set("never", forKey: PreferencesStore.Key.quitConfirmation)
        let quiet = AppDelegate(configuration: never.store())
        let pinned = quiet.terminals.newSession(configuration: .waitingForTermination)
        defer { stop([pinned]) }
        quiet.terminals.togglePin(at: 0)
        quiet.confirmQuit = { _ in askCount += 1; return false }

        XCTAssertTrue(quiet.shouldQuit(during: nil))
        XCTAssertEqual(askCount, 1)
    }

    func testOnlyAQuitEventWithAReasonEndsTheSession() {
        XCTAssertFalse(QuitConfirmationAlert.isSessionEnding(nil))
        XCTAssertFalse(QuitConfirmationAlert.isSessionEnding(quitEvent(reason: nil)))
        XCTAssertTrue(QuitConfirmationAlert.isSessionEnding(quitEvent(reason: 0x7273_646E))) // 'rsdn'
    }

    private func quitEvent(reason: OSType?) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(
            eventClass: QuitConfirmationAlert.coreEventClass,
            eventID: QuitConfirmationAlert.quitEventID,
            targetDescriptor: nil,
            returnID: -1,
            transactionID: 0
        )
        if let reason {
            event.setParam(
                NSAppleEventDescriptor(enumCode: reason),
                forKeyword: QuitConfirmationAlert.quitReasonKeyword
            )
        }
        return event
    }

    private func stop(_ sessions: [TerminalSession]) {
        for session in sessions {
            session.onExit = nil
            session.terminate()
        }
    }
}
