import XCTest
@testable import Shade

final class ShellIntegrationTests: XCTestCase {
    private func parse(_ env: [String]) -> [String: String] {
        var dict: [String: String] = [:]
        for entry in env {
            guard let eq = entry.firstIndex(of: "=") else { continue }
            dict[String(entry[..<eq])] = String(entry[entry.index(after: eq)...])
        }
        return dict
    }

    func testSupportedShells() {
        XCTAssertTrue(ShellIntegration.isSupported(shellName: "zsh"))
        XCTAssertFalse(ShellIntegration.isSupported(shellName: "bash"))
        XCTAssertFalse(ShellIntegration.isSupported(shellName: "fish"))
    }

    func testDisabledReturnsNil() {
        XCTAssertNil(ShellIntegration.environment(shellName: "zsh", enabled: false))
    }

    func testNonZshReturnsNilEvenWhenEnabled() {
        XCTAssertNil(ShellIntegration.environment(shellName: "bash", enabled: true))
    }

    func testInjectsZdotdirWiring() {
        let env = parse(ShellIntegration.makeEnvironment(
            shimPath: "/shim", integrationPath: "/integ",
            processEnv: ["HOME": "/Users/jane"]))
        XCTAssertEqual(env["ZDOTDIR"], "/shim")
        XCTAssertEqual(env["SHADE_USER_ZDOTDIR"], "/Users/jane")  // no user ZDOTDIR → HOME
        XCTAssertEqual(env["SHADE_INTEGRATION_DIR"], "/integ")
        XCTAssertEqual(env["SHADE_INJECTION"], "1")
    }

    func testHonoursExistingUserZdotdir() {
        let env = parse(ShellIntegration.makeEnvironment(
            shimPath: "/shim", integrationPath: "/integ",
            processEnv: ["HOME": "/Users/jane", "ZDOTDIR": "/Users/jane/.config/zsh"]))
        XCTAssertEqual(env["SHADE_USER_ZDOTDIR"], "/Users/jane/.config/zsh")
    }

    func testReplicatesTerminalDefaultsAndPreservesIdentity() {
        let env = parse(ShellIntegration.makeEnvironment(
            shimPath: "/shim", integrationPath: "/integ",
            processEnv: ["HOME": "/Users/jane", "USER": "jane", "LOGNAME": "jane"]))
        XCTAssertEqual(env["TERM"], "xterm-256color")
        XCTAssertEqual(env["COLORTERM"], "truecolor")
        XCTAssertEqual(env["LANG"], "en_US.UTF-8")
        XCTAssertEqual(env["HOME"], "/Users/jane")
        XCTAssertEqual(env["USER"], "jane")
        XCTAssertEqual(env["LOGNAME"], "jane")
    }

    func testOmitsPathSoLoginShellRebuildsIt() {
        // Passing PATH would shadow the login shell's path_helper reconstruction;
        // today's nil path omits it, so we must too.
        let env = parse(ShellIntegration.makeEnvironment(
            shimPath: "/shim", integrationPath: "/integ",
            processEnv: ["HOME": "/Users/jane", "PATH": "/usr/bin:/bin"]))
        XCTAssertNil(env["PATH"])
    }
}
