import XCTest
@testable import Shade

final class TerminalLaunchConfigurationTests: XCTestCase {
    func testDefaultConfigurationStartsAnOrdinaryLocalShell() {
        let configuration = TerminalLaunchConfiguration()

        XCTAssertNil(configuration.startupDirectory)
        XCTAssertNil(configuration.title)
        XCTAssertNil(configuration.initialCommand)
        XCTAssertNil(configuration.initialInput)
    }

    func testInitialInputRendersOneCommandFollowedByTerminalEnter() {
        let configuration = TerminalLaunchConfiguration(
            initialCommand: ProcessInvocation(
                executable: "/usr/bin/printf",
                arguments: ["%s", "hello world"]
            )
        )

        XCTAssertEqual(
            configuration.initialInput.map { String(decoding: $0, as: UTF8.self) },
            "/usr/bin/printf %s 'hello world'\r"
        )
    }

    func testSSHProfileProducesNamedGenericLaunchConfiguration() throws {
        let configuration = try SSHConnectionLaunch.configuration(
            for: SSHProfile(
                name: "  Production EU  ",
                host: "production",
                username: "deploy",
                port: 2_222,
                identityFile: "~/.ssh/prod key"
            ),
            homeDirectory: "/Users/tester"
        )

        XCTAssertEqual(configuration.title, "Production EU")
        XCTAssertEqual(
            configuration.initialCommand,
            ProcessInvocation(
                executable: "/usr/bin/ssh",
                arguments: [
                    "-p", "2222",
                    "-l", "deploy",
                    "-i", "/Users/tester/.ssh/prod key",
                    "production",
                ]
            )
        )
        XCTAssertNil(configuration.startupDirectory)
    }

    func testInvalidSSHProfileFailsBeforeCreatingConfiguration() {
        XCTAssertThrowsError(
            try SSHConnectionLaunch.configuration(
                for: SSHProfile(name: "Production", host: "-oProxyCommand=unexpected")
            )
        ) { error in
            XCTAssertEqual(error as? SSHProfileValidationError, .hostStartsWithDash)
        }
    }

    func testConfiguredTitleIsPinnedOnTerminalSession() async {
        await MainActor.run {
            let session = TerminalSession(
                configuration: TerminalLaunchConfiguration(title: "Production EU")
            )

            XCTAssertEqual(session.userTitle, "Production EU")
            XCTAssertEqual(session.displayTitle, "Production EU")
        }
    }

    func testControllerRejectsInvalidProfileWithoutAddingTab() async {
        await MainActor.run {
            let controller = TerminalsController()

            do {
                _ = try controller.connect(
                    to: SSHProfile(name: "Production", host: "-oProxyCommand=unexpected")
                )
                XCTFail("Invalid profile unexpectedly created a terminal session")
            } catch {
                XCTAssertEqual(error as? SSHProfileValidationError, .hostStartsWithDash)
            }
            XCTAssertTrue(controller.sessions.isEmpty)
            XCTAssertEqual(controller.activeIndex, -1)
        }
    }
}
