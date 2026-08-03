import XCTest
@testable import Shade

final class TerminalLinkOpenerTests: XCTestCase {
    func testFileUrlIsAlwaysRevealed() {
        let url = URL(fileURLWithPath: "/tmp/report.txt")

        XCTAssertEqual(
            TerminalLinkOpener.resolve(url.absoluteString, cwd: "", fileExists: { _ in false }),
            .reveal(url)
        )
    }

    func testExistingAbsolutePathIsRevealed() {
        XCTAssertEqual(
            TerminalLinkOpener.resolve("/tmp/report.txt", cwd: "", fileExists: { $0 == "/tmp/report.txt" }),
            .reveal(URL(fileURLWithPath: "/tmp/report.txt"))
        )
    }

    func testRelativePathUsesShellCwd() {
        XCTAssertEqual(
            TerminalLinkOpener.resolve("Sources/main.swift", cwd: "/repo", fileExists: {
                $0 == "/repo/Sources/main.swift"
            }),
            .reveal(URL(fileURLWithPath: "/repo/Sources/main.swift"))
        )
    }

    func testWebUrlUsesDefaultHandler() {
        let url = URL(string: "https://example.com/docs")!

        XCTAssertEqual(
            TerminalLinkOpener.resolve(url.absoluteString, cwd: "", fileExists: { _ in false }),
            .open(url)
        )
    }

    func testMissingSchemelessPathIsIgnored() {
        XCTAssertNil(TerminalLinkOpener.resolve("not-a-link", cwd: "/repo", fileExists: { _ in false }))
    }
}
