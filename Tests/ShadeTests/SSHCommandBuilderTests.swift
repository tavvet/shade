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

    func testMetacharactersRemainLiteralStructuredArguments() throws {
        let invocation = try SSHCommandBuilder.invocation(
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
            invocation.arguments,
            [
                "-p", "2222",
                "-l", "deploy$(touch)",
                "-i", "/Users/tester/.ssh/O'Brien key",
                "prod;touch-owned",
            ]
        )
    }

    func testBuilderRejectsHostOptionInjectionBeforeLaunching() {
        XCTAssertThrowsError(
            try SSHCommandBuilder.invocation(
                for: SSHProfile(name: "Unexpected", host: "-oProxyCommand=touch")
            )
        ) { error in
            XCTAssertEqual(error as? SSHProfileValidationError, .hostStartsWithDash)
        }
    }
}
