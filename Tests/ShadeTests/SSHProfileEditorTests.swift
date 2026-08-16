import XCTest
@testable import Shade

final class SSHProfileEditorTests: XCTestCase {
    func testDraftRoundTripParsesPortAndNormalizesFields() throws {
        let id = UUID()
        var draft = SSHProfileDraft(
            profile: SSHProfile(id: id, name: "Old", host: "old")
        )
        draft.name = "  Production EU  "
        draft.host = " production "
        draft.username = " deploy "
        draft.port = " 2222 "
        draft.identityFile = " ~/.ssh/prod "

        XCTAssertEqual(
            try draft.makeProfile(),
            SSHProfile(
                id: id,
                name: "Production EU",
                host: "production",
                username: "deploy",
                port: 2_222,
                identityFile: "~/.ssh/prod"
            )
        )
    }

    func testBlankOptionalFieldsBecomeNil() throws {
        var draft = SSHProfileDraft(
            profile: SSHProfile(
                name: "Production",
                host: "prod",
                username: "deploy",
                port: 22,
                identityFile: "~/.ssh/prod"
            )
        )
        draft.username = "  "
        draft.port = ""
        draft.identityFile = "\n"

        let profile = try draft.makeProfile()

        XCTAssertNil(profile.username)
        XCTAssertNil(profile.port)
        XCTAssertNil(profile.identityFile)
    }

    func testNonNumericPortProducesEditorSpecificError() {
        var draft = SSHProfileDraft(
            profile: SSHProfile(name: "Production", host: "prod")
        )
        draft.port = "22.5"

        XCTAssertThrowsError(try draft.makeProfile()) { error in
            XCTAssertEqual(error as? SSHProfileDraftError, .invalidPort("22.5"))
        }
    }

    func testNumericPortStillUsesDomainRangeValidation() {
        var draft = SSHProfileDraft(
            profile: SSHProfile(name: "Production", host: "prod")
        )
        draft.port = "65536"

        XCTAssertThrowsError(try draft.makeProfile()) { error in
            XCTAssertEqual(error as? SSHProfileValidationError, .invalidPort(65_536))
        }
    }

    func testDestinationLabelsHandleAliasUserPortAndIPv6() {
        XCTAssertEqual(
            SSHProfileDisplay.destinationLabel(
                SSHProfile(name: "Production", host: "production")
            ),
            "production"
        )
        XCTAssertEqual(
            SSHProfileDisplay.destinationLabel(
                SSHProfile(
                    name: "Production",
                    host: "prod.example.com",
                    username: "deploy",
                    port: 2_222
                )
            ),
            "deploy@prod.example.com:2222"
        )
        XCTAssertEqual(
            SSHProfileDisplay.destinationLabel(
                SSHProfile(name: "IPv6", host: "2001:db8::1", port: 22)
            ),
            "[2001:db8::1]:22"
        )
    }
}
