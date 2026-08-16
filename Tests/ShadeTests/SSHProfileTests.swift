import XCTest
@testable import Shade

final class SSHProfileTests: XCTestCase {
    func testNormalizationTrimsFieldsAndDropsBlankOptionals() throws {
        let id = UUID()
        let normalized = try SSHProfile(
            id: id,
            name: "  Production EU  ",
            host: "  production  ",
            username: " deploy ",
            port: 22,
            identityFile: "   "
        ).normalized()

        XCTAssertEqual(
            normalized,
            SSHProfile(
                id: id,
                name: "Production EU",
                host: "production",
                username: "deploy",
                port: 22,
                identityFile: nil
            )
        )
    }

    func testNameAndHostAreRequired() {
        assertValidation(
            SSHProfile(name: "  ", host: "prod"),
            equals: .nameRequired
        )
        assertValidation(
            SSHProfile(name: "Production", host: "\n"),
            equals: .hostRequired
        )
    }

    func testHostCannotBeParsedAsAnSSHOptionOrContainWhitespace() {
        assertValidation(
            SSHProfile(name: "Production", host: "-oProxyCommand=unexpected"),
            equals: .hostStartsWithDash
        )
        assertValidation(
            SSHProfile(name: "Production", host: "prod server"),
            equals: .hostContainsWhitespace
        )
    }

    func testUsernameCannotContainWhitespace() {
        assertValidation(
            SSHProfile(name: "Production", host: "prod", username: "deploy user"),
            equals: .usernameContainsWhitespace
        )
    }

    func testPortMustFitOpenSSHRange() {
        assertValidation(
            SSHProfile(name: "Production", host: "prod", port: 0),
            equals: .invalidPort(0)
        )
        assertValidation(
            SSHProfile(name: "Production", host: "prod", port: 65_536),
            equals: .invalidPort(65_536)
        )
        XCTAssertNoThrow(try SSHProfile(name: "Production", host: "prod", port: 65_535).normalized())
    }

    func testControlCharactersAreRejectedInEveryTextField() {
        assertValidation(
            SSHProfile(name: "Prod\u{0}uction", host: "prod"),
            equals: .controlCharacters(.name)
        )
        assertValidation(
            SSHProfile(name: "Production", host: "prod\u{0}host"),
            equals: .controlCharacters(.host)
        )
        assertValidation(
            SSHProfile(name: "Production", host: "prod", username: "de\u{7}ploy"),
            equals: .controlCharacters(.username)
        )
        assertValidation(
            SSHProfile(name: "Production", host: "prod", identityFile: "key\nfile"),
            equals: .controlCharacters(.identityFile)
        )
    }

    private func assertValidation(
        _ profile: SSHProfile,
        equals expected: SSHProfileValidationError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try profile.normalized(), file: file, line: line) { error in
            XCTAssertEqual(error as? SSHProfileValidationError, expected, file: file, line: line)
        }
    }
}
