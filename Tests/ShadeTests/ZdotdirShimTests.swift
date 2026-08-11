import XCTest

final class ZdotdirShimTests: XCTestCase {
    func testUnsetZdotdirLoadsHomeStartupFilesAndRemainsUnset() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writeStartupChain(in: fixture.home)

        let result = try fixture.run(userZdotdir: fixture.home.path, wasSet: false)

        XCTAssertEqual(result.stages, ["zshenv", "zprofile", "zshrc", "zlogin"])
        XCTAssertEqual(result.finalZdotdir, .unset)
    }

    func testZdotdirChangesRouteEveryFollowingStartupFile() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let profileDirectory = fixture.directory(named: "profile")
        let rcDirectory = fixture.directory(named: "rc")
        let loginDirectory = fixture.directory(named: "login")
        try fixture.createDirectories([profileDirectory, rcDirectory, loginDirectory])

        try fixture.write(
            ".zshenv",
            in: fixture.home,
            stage: "zshenv",
            command: "export ZDOTDIR=\"$HOME/profile\""
        )
        try fixture.write(
            ".zprofile",
            in: profileDirectory,
            stage: "zprofile",
            command: "export ZDOTDIR=\"$HOME/rc\""
        )
        try fixture.write(
            ".zshrc",
            in: rcDirectory,
            stage: "zshrc",
            command: "compdef() { : }\nexport ZDOTDIR=\"$HOME/login\""
        )
        try fixture.write(".zlogin", in: loginDirectory, stage: "zlogin")

        let result = try fixture.run(userZdotdir: fixture.home.path, wasSet: false)

        XCTAssertEqual(result.stages, ["zshenv", "zprofile", "zshrc", "zlogin"])
        XCTAssertEqual(result.finalZdotdir, .set(loginDirectory.path))
    }

    func testCustomZdotdirLoadsCustomStartupFilesAndRemainsSet() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let custom = fixture.directory(named: "custom config")
        try fixture.createDirectories([custom])
        try fixture.writeStartupChain(in: custom)

        let result = try fixture.run(userZdotdir: custom.path, wasSet: true)

        XCTAssertEqual(result.stages, ["zshenv", "zprofile", "zshrc", "zlogin"])
        XCTAssertEqual(result.finalZdotdir, .set(custom.path))
    }

    func testUserZshenvCanUnsetCustomZdotdirAndReturnToHome() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let custom = fixture.directory(named: "custom")
        try fixture.createDirectories([custom])
        try fixture.write(
            ".zshenv",
            in: custom,
            stage: "zshenv",
            command: "unset ZDOTDIR"
        )
        try fixture.write(".zprofile", in: fixture.home, stage: "zprofile")
        try fixture.write(
            ".zshrc",
            in: fixture.home,
            stage: "zshrc",
            command: "compdef() { : }"
        )
        try fixture.write(".zlogin", in: fixture.home, stage: "zlogin")

        let result = try fixture.run(userZdotdir: custom.path, wasSet: true)

        XCTAssertEqual(result.stages, ["zshenv", "zprofile", "zshrc", "zlogin"])
        XCTAssertEqual(result.finalZdotdir, .unset)
    }

    func testDisablingRcsBeforeFinalStageRestoresUserZdotdir() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.write(".zshenv", in: fixture.home, stage: "zshenv")
        try fixture.write(
            ".zprofile",
            in: fixture.home,
            stage: "zprofile",
            command: "unsetopt RCS"
        )
        try fixture.write(
            ".zshrc",
            in: fixture.home,
            stage: "zshrc",
            command: "compdef() { : }"
        )
        try fixture.write(".zlogin", in: fixture.home, stage: "zlogin")

        let result = try fixture.run(userZdotdir: fixture.home.path, wasSet: false)

        XCTAssertEqual(result.stages, ["zshenv", "zprofile"])
        XCTAssertEqual(result.finalZdotdir, .unset)
    }

    func testEmptyZdotdirSkipsHomeStartupFilesAndRemainsSet() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writeStartupChain(in: fixture.home)

        let result = try fixture.run(userZdotdir: "", wasSet: true)

        XCTAssertEqual(result.stages, [])
        XCTAssertEqual(result.finalZdotdir, .set(""))
    }

    func testUserZshenvCanSetEmptyZdotdir() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.write(
            ".zshenv",
            in: fixture.home,
            stage: "zshenv",
            command: "export ZDOTDIR=\"\""
        )
        try fixture.write(".zprofile", in: fixture.home, stage: "zprofile")
        try fixture.write(
            ".zshrc",
            in: fixture.home,
            stage: "zshrc",
            command: "compdef() { : }"
        )
        try fixture.write(".zlogin", in: fixture.home, stage: "zlogin")

        let result = try fixture.run(userZdotdir: fixture.home.path, wasSet: false)

        XCTAssertEqual(result.stages, ["zshenv"])
        XCTAssertEqual(result.finalZdotdir, .set(""))
    }
}

private struct Fixture {
    enum ZdotdirState: Equatable {
        case unset
        case set(String)
    }

    struct RunResult {
        let stages: [String]
        let finalZdotdir: ZdotdirState
    }

    let root: URL
    let home: URL
    private let log: URL
    private let cache: URL
    private let integrationDirectory: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("shade-zdotdir-tests-\(UUID().uuidString)", isDirectory: true)
        home = root.appendingPathComponent("home", isDirectory: true)
        log = root.appendingPathComponent("stages.log")
        cache = root.appendingPathComponent("cache", isDirectory: true)
        integrationDirectory = root.appendingPathComponent("integration", isDirectory: true)
        try createDirectories([home, cache, integrationDirectory])
    }

    func directory(named name: String) -> URL {
        home.appendingPathComponent(name, isDirectory: true)
    }

    func createDirectories(_ directories: [URL]) throws {
        for directory in directories {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
    }

    func writeStartupChain(in directory: URL) throws {
        try write(".zshenv", in: directory, stage: "zshenv")
        try write(".zprofile", in: directory, stage: "zprofile")
        try write(".zshrc", in: directory, stage: "zshrc", command: "compdef() { : }")
        try write(".zlogin", in: directory, stage: "zlogin")
    }

    func write(
        _ name: String,
        in directory: URL,
        stage: String,
        command: String = ""
    ) throws {
        let contents = "print -r -- \(stage) >> \"$SHADE_TEST_LOG\"\n\(command)\n"
        try contents.write(
            to: directory.appendingPathComponent(name),
            atomically: true,
            encoding: .utf8
        )
    }

    func run(userZdotdir: String, wasSet: Bool) throws -> RunResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            "-lic",
            "print -r -- \"SHADE_RESULT:${+ZDOTDIR}:${ZDOTDIR-<unset>}\"",
        ]
        process.environment = [
            "HOME": home.path,
            "ZDOTDIR": Self.shimDirectory.path,
            "SHADE_SHIM_ZDOTDIR": Self.shimDirectory.path,
            "SHADE_USER_ZDOTDIR": userZdotdir,
            "SHADE_USER_ZDOTDIR_SET": wasSet ? "1" : "0",
            "SHADE_INTEGRATION_DIR": integrationDirectory.path,
            "SHADE_INJECTION": "1",
            "SHADE_TEST_LOG": log.path,
            "XDG_CACHE_HOME": cache.path,
            "TERM": "xterm-256color",
        ]
        process.currentDirectoryURL = home
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        let output = String(
            data: stdout.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let errors = String(
            data: stderr.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        guard process.terminationStatus == 0 else {
            throw ShimTestError.zshFailed(process.terminationStatus, errors)
        }
        guard let marker = output
            .split(whereSeparator: \Character.isNewline)
            .map(String.init)
            .last(where: { $0.hasPrefix("SHADE_RESULT:") })
        else {
            throw ShimTestError.missingResult(output, errors)
        }

        let fields = marker.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        let state: ZdotdirState = fields[1] == "0"
            ? .unset
            : .set(String(fields[2]))
        let stages = (try? String(contentsOf: log, encoding: .utf8))?
            .split(whereSeparator: \Character.isNewline)
            .map(String.init) ?? []
        return RunResult(stages: stages, finalZdotdir: state)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    private static let shimDirectory: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("integrations/zdotdir", isDirectory: true)
}

private enum ShimTestError: Error {
    case zshFailed(Int32, String)
    case missingResult(String, String)
}
