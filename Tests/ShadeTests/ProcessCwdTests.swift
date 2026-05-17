import XCTest
import Darwin
@testable import Shade

final class ProcessCwdTests: XCTestCase {
    func testReadsOwnProcessCwd() {
        let actual = FileManager.default.currentDirectoryPath
        let reported = ProcessCwd.read(pid: getpid())
        XCTAssertEqual(reported, actual)
    }

    func testRejectsInvalidPid() {
        XCTAssertNil(ProcessCwd.read(pid: 0))
        XCTAssertNil(ProcessCwd.read(pid: -1))
    }

    func testReadsNothingForNonexistentPid() {
        // 0x7FFFFFFF is well beyond any plausible live PID on macOS.
        XCTAssertNil(ProcessCwd.read(pid: 0x7FFFFFFF))
    }
}
