import XCTest
@testable import Shade

final class SSHConnectionPickerSearchTests: XCTestCase {
    private let profiles = [
        SSHProfile(
            name: "Production Europe",
            host: "prod.example.com",
            username: "deploy",
            port: 2_222,
            identityFile: "~/.ssh/prod"
        ),
        SSHProfile(name: "Staging", host: "stage.internal"),
        SSHProfile(name: "Database", host: "db.example.com", username: "postgres"),
    ]

    func testBlankQueryPreservesLibraryOrder() {
        XCTAssertEqual(SSHConnectionPickerSearch.matches(profiles, query: "  "), profiles)
    }

    func testSearchCoversProfileFields() {
        XCTAssertEqual(matches("europe").map(\.name), ["Production Europe"])
        XCTAssertEqual(matches("stage.internal").map(\.name), ["Staging"])
        XCTAssertEqual(matches("postgres").map(\.name), ["Database"])
        XCTAssertEqual(matches("2222").map(\.name), ["Production Europe"])
        XCTAssertEqual(matches(".ssh/prod").map(\.name), ["Production Europe"])
    }

    func testEveryTokenMustMatch() {
        XCTAssertEqual(matches("deploy prod").map(\.name), ["Production Europe"])
        XCTAssertTrue(matches("deploy staging").isEmpty)
    }

    func testMatchingIsCaseAndDiacriticInsensitive() {
        let accented = [SSHProfile(name: "Montréal", host: "ca.example.com")]
        XCTAssertEqual(
            SSHConnectionPickerSearch.matches(accented, query: "MONTREAL"),
            accented
        )
    }

    private func matches(_ query: String) -> [SSHProfile] {
        SSHConnectionPickerSearch.matches(profiles, query: query)
    }
}
