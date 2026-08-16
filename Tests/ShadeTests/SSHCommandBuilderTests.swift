import XCTest
@testable import Shade

final class SSHCommandBuilderTests: XCTestCase {
    func testMinimalProfileUsesSystemOpenSSHAndConfigAlias() throws {
        let invocation = try SSHCommandBuilder.invocation(
            for: SSHProfile(name: "Production", host: "production")
        )

        XCTAssertEqual(
            invocation,
            ProcessInvocation(executable: "/usr/bin/ssh", arguments: ["production"])
        )
    }

    func testOptionalValuesBecomeSeparateArgumentsAndTildeIsExpanded() throws {
        let invocation = try SSHCommandBuilder.invocation(
            for: SSHProfile(
                name: "Production",
                host: "prod.example.com",
                username: "deploy",
                port: 2_222,
                identityFile: "~/.ssh/prod key"
            ),
            homeDirectory: "/Users/tester"
        )

        XCTAssertEqual(
            invocation.arguments,
            [
                "-p", "2222",
                "-l", "deploy",
                "-i", "/Users/tester/.ssh/prod key",
                "prod.example.com",
            ]
        )
    }

    func testShellCommandQuotesMetacharactersAndSingleQuotes() throws {
        let command = try SSHCommandBuilder.shellCommand(
            for: SSHProfile(
                name: "Production",
                host: "prod;touch-owned",
                username: "deploy$(touch)",
                port: 2_222,
                identityFile: "~/.ssh/O'Brien key"
            ),
            homeDirectory: "/Users/tester"
        )

        XCTAssertEqual(
            command,
            "/usr/bin/ssh -p 2222 -l 'deploy$(touch)' "
                + "-i '/Users/tester/.ssh/O'\\''Brien key' 'prod;touch-owned'"
        )
    }

    func testRendererQuotesEmptyAndUnsafeArgumentsButLeavesSimpleOnesReadable() {
        XCTAssertEqual(ShellCommandRenderer.quote(""), "''")
        XCTAssertEqual(ShellCommandRenderer.quote("prod.example.com"), "prod.example.com")
        XCTAssertEqual(ShellCommandRenderer.quote("$(touch /tmp/nope)"), "'$(touch /tmp/nope)'")
        XCTAssertEqual(ShellCommandRenderer.quote("O'Brien"), "'O'\\''Brien'")
    }

    func testBuilderRejectsHostOptionInjectionBeforeRendering() {
        XCTAssertThrowsError(
            try SSHCommandBuilder.shellCommand(
                for: SSHProfile(name: "Unexpected", host: "-oProxyCommand=touch")
            )
        ) { error in
            XCTAssertEqual(error as? SSHProfileValidationError, .hostStartsWithDash)
        }
    }
}
