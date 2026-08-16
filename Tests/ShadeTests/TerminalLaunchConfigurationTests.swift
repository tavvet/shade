import XCTest
@testable import Shade

final class TerminalLaunchConfigurationTests: XCTestCase {
    func testDefaultConfigurationStartsAnOrdinaryLocalShell() {
        let configuration = TerminalLaunchConfiguration()

        XCTAssertNil(configuration.startupDirectory)
        XCTAssertNil(configuration.title)
        XCTAssertNil(configuration.initialCommand)
    }

    func testCommandSequenceKeepsEnvironmentAndCommandArgumentsStructured() throws {
        let command = ProcessInvocation(
            executable: "/usr/bin/printf",
            arguments: ["%s", "hello; $(unexpected)"]
        )
        let invocation = TerminalCommandSequence.invocation(
            initialCommand: command,
            loginShellPath: "/bin/zsh"
        )
        let environment = Set(TerminalCommandSequence.environment(
            inheritedEnvironment: [
                "LANG": "fi_FI.UTF-8",
                "PATH": "/custom/bin:/usr/bin",
                "SSH_AUTH_SOCK": "/tmp/agent socket",
                "TERM": "unexpected",
            ],
            shellIntegrationEnvironment: nil,
            homeDirectory: "/Users/tester"
        ))

        XCTAssertEqual(invocation.executable, "/bin/sh")
        XCTAssertEqual(
            Array(invocation.arguments.prefix(5)),
            [
                "-c",
                TerminalCommandSequence.wrapperScript,
                "shade-command-sequence",
                "/bin/zsh",
                "/usr/bin/printf",
            ]
        )
        XCTAssertTrue(environment.contains("COLORTERM=truecolor"))
        XCTAssertTrue(environment.contains("HOME=/Users/tester"))
        XCTAssertTrue(environment.contains("LANG=fi_FI.UTF-8"))
        XCTAssertTrue(environment.contains("PATH=/custom/bin:/usr/bin"))
        XCTAssertTrue(environment.contains("SSH_AUTH_SOCK=/tmp/agent socket"))
        XCTAssertTrue(environment.contains("TERM=xterm-256color"))
        XCTAssertEqual(
            Array(invocation.arguments.suffix(3)),
            ["/usr/bin/printf", "%s", "hello; $(unexpected)"]
        )
    }

    func testCommandSequenceSuppliesEssentialMissingEnvironment() {
        let environment = Set(TerminalCommandSequence.environment(
            inheritedEnvironment: [:],
            shellIntegrationEnvironment: nil,
            homeDirectory: "/Users/tester"
        ))

        XCTAssertTrue(environment.contains("HOME=/Users/tester"))
        XCTAssertTrue(environment.contains("LANG=en_US.UTF-8"))
        XCTAssertTrue(environment.contains("PATH=\(TerminalCommandSequence.defaultExecutablePath)"))
    }

    func testCommandSequenceDropsStaleInheritedShellIntegrationWhenDisabled() {
        let environment = Set(TerminalCommandSequence.environment(
            inheritedEnvironment: [
                "HOME": "/Users/tester",
                "ZDOTDIR": "/Users/tester/.config/zsh",
                "SHADE_SEQUENCE_HAS_INTEGRATION": "1",
                "SHADE_SHIM_ZDOTDIR": "/old-shade-shim",
                "SHADE_USER_ZDOTDIR": "/Users/tester",
                "SHADE_USER_ZDOTDIR_SET": "1",
                "SHADE_INTEGRATION_DIR": "/old-shade-integrations",
                "SHADE_INJECTION": "1",
            ],
            shellIntegrationEnvironment: nil,
            homeDirectory: "/Users/tester"
        ))

        XCTAssertTrue(environment.contains("ZDOTDIR=/Users/tester/.config/zsh"))
        XCTAssertFalse(environment.contains(where: { $0.hasPrefix("SHADE_") }))
    }

    func testCommandSequenceScopesShellIntegrationToFallbackShell() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShadeCommandEnvironmentTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let loginShell = directory.appendingPathComponent("environment-shell")
        try Data("#!/bin/sh\necho __LOGIN_SHELL__\n/usr/bin/env\n".utf8).write(to: loginShell)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: loginShell.path
        )

        let invocation = TerminalCommandSequence.invocation(
            initialCommand: ProcessInvocation(executable: "/usr/bin/env", arguments: []),
            loginShellPath: loginShell.path
        )
        let environment = TerminalCommandSequence.environment(
            inheritedEnvironment: [
                "HOME": "/Users/tester",
                "PATH": "/custom/bin:/usr/bin",
                "SSH_AUTH_SOCK": "/tmp/agent.sock",
                "ZDOTDIR": "/original-zdotdir",
            ],
            shellIntegrationEnvironment: [
                "ZDOTDIR=/shade-shim",
                "SHADE_SHIM_ZDOTDIR=/shade-shim",
                "SHADE_USER_ZDOTDIR=/original-zdotdir",
                "SHADE_USER_ZDOTDIR_SET=1",
                "SHADE_INTEGRATION_DIR=/shade-integrations",
                "SHADE_INJECTION=1",
            ]
        )
        let process = Process()
        process.executableURL = URL(fileURLWithPath: invocation.executable)
        process.arguments = invocation.arguments
        process.environment = Dictionary(uniqueKeysWithValues: environment.compactMap { entry in
            let parts = entry.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            return (String(parts[0]), String(parts[1]))
        })
        let output = Pipe()
        process.standardOutput = output

        try process.run()
        process.waitUntilExit()
        let text = String(
            decoding: output.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        let sections = text.components(separatedBy: "__LOGIN_SHELL__\n")
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(sections.count, 2)
        XCTAssertTrue(sections[0].contains("SSH_AUTH_SOCK=/tmp/agent.sock\n"))
        XCTAssertTrue(sections[0].contains("ZDOTDIR=/original-zdotdir\n"))
        XCTAssertFalse(sections[0].contains("SHADE_INJECTION="))
        XCTAssertTrue(sections[1].contains("SSH_AUTH_SOCK=/tmp/agent.sock\n"))
        XCTAssertTrue(sections[1].contains("ZDOTDIR=/shade-shim\n"))
        XCTAssertTrue(sections[1].contains("SHADE_INJECTION=1\n"))
    }

    @MainActor
    func testProcessControllerCompletesCommandAndLoginShellInOneProcessLifecycle() {
        var didExit = false
        let controller = TerminalProcessController(
            configuration: TerminalLaunchConfiguration(
                initialCommand: ProcessInvocation(
                    executable: "/usr/bin/true",
                    arguments: []
                )
            ),
            shellPath: "/usr/bin/true"
        )
        controller.onExit = { didExit = true }

        controller.start()

        let deadline = Date().addingTimeInterval(3)
        while !didExit, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(didExit, "Command wrapper did not continue through the login-shell stage")
    }

    @MainActor
    func testProcessControllerRetriesAfterPTYLaunchFailure() {
        var attempts = 0
        let controller = TerminalProcessController(
            shellPath: "/bin/zsh",
            processStarter: { _, _, _, _, _, _ in
                attempts += 1
                return attempts > 1
            }
        )

        controller.start()
        controller.start()
        controller.start()

        XCTAssertEqual(attempts, 2)
    }

    @MainActor
    func testTerminatingCommandSequenceDoesNotStartLoginShell() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShadeCommandSequenceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let marker = directory.appendingPathComponent("login-shell-started")
        let shell = directory.appendingPathComponent("marker-shell")
        try Data("#!/bin/sh\n/usr/bin/touch '\(marker.path)'\n".utf8).write(to: shell)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: shell.path
        )

        var didExit = false
        let controller = TerminalProcessController(
            configuration: TerminalLaunchConfiguration(
                initialCommand: ProcessInvocation(
                    executable: "/bin/sleep",
                    arguments: ["5"]
                )
            ),
            shellPath: shell.path
        )
        controller.onExit = { didExit = true }
        controller.start()
        controller.terminate()

        let deadline = Date().addingTimeInterval(3)
        while !didExit, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(didExit)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
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
