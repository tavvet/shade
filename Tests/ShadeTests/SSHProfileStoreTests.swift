import Foundation
import XCTest
@testable import Shade

final class SSHProfileStoreTests: XCTestCase {
    func testMissingFileLoadsAsEmptyLibrary() throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanup() }

        XCTAssertEqual(try fixture.store.load(), [])
    }

    func testSaveCreatesPrivateVersionedFileAndPreservesOrder() throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanup() }
        let firstID = UUID()
        let secondID = UUID()

        try fixture.store.save([
            SSHProfile(
                id: firstID,
                name: "  Production  ",
                host: " prod ",
                username: " deploy ",
                identityFile: "   "
            ),
            SSHProfile(id: secondID, name: "Staging", host: "stage", port: 2_222),
        ])

        XCTAssertEqual(
            try fixture.store.load(),
            [
                SSHProfile(
                    id: firstID,
                    name: "Production",
                    host: "prod",
                    username: "deploy"
                ),
                SSHProfile(id: secondID, name: "Staging", host: "stage", port: 2_222),
            ]
        )

        let data = try Data(contentsOf: fixture.fileURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, SSHProfileStore.currentVersion)

        let attributes = try FileManager.default.attributesOfItem(atPath: fixture.fileURL.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        XCTAssertEqual(permissions.intValue & 0o777, 0o600)
    }

    func testDuplicateNamesAreRejectedCaseInsensitively() throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanup() }

        XCTAssertThrowsError(
            try fixture.store.save([
                SSHProfile(name: "Production", host: "prod-a"),
                SSHProfile(name: "production", host: "prod-b"),
            ])
        ) { error in
            XCTAssertEqual(error as? SSHProfileStoreError, .duplicateName("production"))
        }
    }

    func testDuplicateNamesUseUnicodeCaseFolding() throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanup() }

        XCTAssertThrowsError(
            try fixture.store.save([
                SSHProfile(name: "Straße", host: "de-a"),
                SSHProfile(name: "STRASSE", host: "de-b"),
            ])
        ) { error in
            XCTAssertEqual(error as? SSHProfileStoreError, .duplicateName("STRASSE"))
        }
    }

    func testUpdatingExistingFileReplacesContentsAndRestoresPrivatePermissions() throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanup() }
        let original = SSHProfile(name: "Production", host: "prod")
        let replacement = SSHProfile(name: "Staging", host: "stage")

        try fixture.store.save([original])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: fixture.fileURL.path
        )
        try fixture.store.save([replacement])

        XCTAssertEqual(try fixture.store.load(), [replacement])
        let attributes = try FileManager.default.attributesOfItem(
            atPath: fixture.fileURL.path
        )
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        XCTAssertEqual(permissions.intValue & 0o777, 0o600)
    }

    func testDuplicateIdentifiersAreRejected() throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanup() }
        let id = UUID()

        XCTAssertThrowsError(
            try fixture.store.save([
                SSHProfile(id: id, name: "Production", host: "prod"),
                SSHProfile(id: id, name: "Staging", host: "stage"),
            ])
        ) { error in
            XCTAssertEqual(error as? SSHProfileStoreError, .duplicateID(id))
        }
    }

    func testUnsupportedVersionFailsWithoutRewritingFile() throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanup() }
        try fixture.write(#"{"profiles":[],"version":2}"#)
        let original = try Data(contentsOf: fixture.fileURL)

        XCTAssertThrowsError(try fixture.store.load()) { error in
            XCTAssertEqual(error as? SSHProfileStoreError, .unsupportedVersion(2))
        }
        XCTAssertEqual(try Data(contentsOf: fixture.fileURL), original)
    }

    func testMalformedJSONIsReportedWithoutRewritingFile() throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanup() }
        try fixture.write("not json")
        let original = try Data(contentsOf: fixture.fileURL)

        XCTAssertThrowsError(try fixture.store.load())
        XCTAssertEqual(try Data(contentsOf: fixture.fileURL), original)
    }
}

private final class StoreFixture {
    let rootURL: URL
    let fileURL: URL
    let store: SSHProfileStore

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShadeSSHProfileStoreTests-\(UUID().uuidString)", isDirectory: true)
        fileURL = rootURL
            .appendingPathComponent("Application Support/Shade", isDirectory: true)
            .appendingPathComponent("connections.json", isDirectory: false)
        store = SSHProfileStore(fileURL: fileURL)
    }

    func write(_ text: String) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(text.utf8).write(to: fileURL)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
