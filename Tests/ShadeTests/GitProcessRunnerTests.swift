import Foundation
import XCTest
@testable import ShadeCore

final class GitProcessRunnerTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try XCTSkipUnless(Self.gitIsUsable, "No usable git; install Git or the Command Line Tools")
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShadeGitRunner-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // A skipped test never created the directory.
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    func testSuccessfulCommandReturnsStandardOutput() async throws {
        try initializeRepository()

        let output = await GitProcessRunner.run(["-C", directory.path, "rev-parse", "--is-inside-work-tree"])

        XCTAssertEqual(output, "true\n")
    }

    func testNonZeroExitReturnsNil() async {
        let output = await GitProcessRunner.run(["-C", directory.path, "rev-parse", "HEAD"])

        XCTAssertNil(output)
    }

    func testLargeStandardErrorDoesNotBlockTheCommand() async throws {
        try initializeRepository()
        let started = Date()

        // Far more than a pipe buffer: an unread stderr pipe would wedge Git.
        let output = await GitProcessRunner.run([
            "-C", directory.path,
            "-c", "alias.noisy=!head -c 1000000 /dev/zero >&2; echo done",
            "noisy",
        ])

        XCTAssertEqual(output, "done\n")
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
    }

    func testCancellationStopsARunningCommand() async throws {
        try initializeRepository()
        let started = Date()
        let path = directory.path
        let task = Task {
            await GitProcessRunner.run(["-C", path, "-c", "alias.slow=!sleep 20", "slow"])
        }

        try await Task.sleep(for: .milliseconds(500))
        task.cancel()
        let output = await task.value

        XCTAssertNil(output)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "cancellation waited for the command to finish")
    }

    func testCancellationBeforeLaunchReturnsNilWithoutRunning() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await GitProcessRunner.run(["--version"])
        }

        let output = await task.value

        XCTAssertNil(output)
    }

    /// True when `/usr/bin/env git` reaches a working Git. The `/usr/bin/git`
    /// shim is used only when Command Line Tools are installed: otherwise
    /// running it opens the developer-tools installation dialog.
    private static let gitIsUsable: Bool = {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        let git = path.split(separator: ":").lazy
            .map { URL(fileURLWithPath: String($0)).appendingPathComponent("git").path }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
        guard let git else { return false }
        if git == "/usr/bin/git", !succeeds("/usr/bin/xcode-select", ["-p"]) { return false }
        return succeeds("/usr/bin/env", ["git", "--version"])
    }()

    private static func succeeds(_ executable: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private func initializeRepository() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "init", "-q", directory.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
