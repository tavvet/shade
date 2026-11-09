import AppKit
import SwiftTerm
import XCTest
@testable import Shade

/// Exercises SwiftTerm's public v1.99.3 request API through its protocol
/// witness, including the checked-URL bridge to Shade's legacy callback.
/// Never install TerminalSession's real NSWorkspace-opening callback here.
@MainActor
final class TerminalLinkDelegateCompatibilityTests: XCTestCase {
    func testExplicitHTTPSRequestReachesShadeCallback() {
        assertForwarded(
            "https://example.test/docs?q=shade#links", isExplicit: true,
            expected: .open(URL(string: "https://example.test/docs?q=shade#links")!)
        )
    }

    func testDetectedHTTPRequestReachesShadeCallback() {
        assertForwarded(
            "http://example.test/docs", isExplicit: false,
            expected: .open(URL(string: "http://example.test/docs")!)
        )
    }

    func testExplicitFileURLIsCheckedAndReachesShadeRevealResolver() {
        let directory = fixtureDirectory
        assertForwarded(directory.absoluteString, isExplicit: true,
                        expected: .reveal(directory))
    }

    func testDetectedAbsoluteDirectoryBecomesCheckedFileURL() {
        let directory = fixtureDirectory
        assertForwarded(directory.path, isExplicit: false,
                        expected: .reveal(directory))
    }

    // An existing ordinary directory is a safe upstream allow target. No
    // fixture writes, executable files, custom schemes or approval dialogs.
    private var fixtureDirectory: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .standardizedFileURL.resolvingSymlinksInPath()
    }

    private func assertForwarded(
        _ link: String, isExplicit: Bool, expected: TerminalLinkOpener.Target,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let view = TerminalView(frame: .zero)
        let proxy = TerminalDelegateProxy(forward: nil)
        view.terminalDelegate = proxy
        var received: [String] = []
        var resolved: [TerminalLinkOpener.Target?] = []
        proxy.onOpenLink = { checkedLink in
            received.append(checkedLink)
            resolved.append(TerminalLinkOpener.resolve(checkedLink, cwd: ""))
        }

        // Use an existential, as SwiftTerm's actual activation does. A direct
        // call to the deprecated overload would miss default-method dispatch.
        let delegate: any TerminalViewDelegate = proxy
        delegate.requestOpenLink(source: view, request: TerminalLinkRequest(
            link: link, params: ["id": "shade-compatibility"], isExplicit: isExplicit
        ))

        // Safe requests must reach the capture synchronously and exactly once.
        // The captured callback only resolves a target; it never opens one.
        XCTAssertEqual(received.count, 1, file: file, line: line)
        XCTAssertEqual(resolved, [expected], file: file, line: line)
        if case .reveal(let url) = expected {
            XCTAssertEqual(received, [url.absoluteString], file: file, line: line)
        } else {
            XCTAssertEqual(received, [link], file: file, line: line)
        }
    }
}
