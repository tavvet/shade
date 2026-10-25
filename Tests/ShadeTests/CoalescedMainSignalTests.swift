import Foundation
import XCTest
@testable import ShadeCore

@MainActor
final class CoalescedMainSignalTests: XCTestCase {
    func testSignalsBeforeTheMainActorRunsShareOneCall() {
        let counter = Counter()
        let signal = CoalescedMainSignal { counter.value += 1 }

        // The main thread is busy here, as during a PTY output burst.
        DispatchQueue.concurrentPerform(iterations: 200) { _ in signal.signal() }
        waitForCondition { counter.value > 0 }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(counter.value, 1)
    }

    func testSignalAfterTheCallSchedulesAnotherCall() {
        let counter = Counter()
        let signal = CoalescedMainSignal { counter.value += 1 }

        signal.signal()
        waitForCondition { counter.value == 1 }
        signal.signal()

        waitForCondition { counter.value == 2 }
    }

    func testSignalRaisedDuringTheCallIsNotLost() {
        let counter = Counter()
        var signal: CoalescedMainSignal?
        signal = CoalescedMainSignal {
            counter.value += 1
            if counter.value == 1 { signal?.signal() }
        }

        signal?.signal()

        waitForCondition { counter.value == 2 }
    }
}

@MainActor
private final class Counter {
    var value = 0
}

final class ShadeCoreBoundaryTests: XCTestCase {
    /// ShadeCore holds UI-free logic; UI and terminal frameworks stay in the app.
    func testShadeCoreDoesNotImportUIOrTerminalFrameworks() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Sources/ShadeCore")
            .standardizedFileURL
        let files = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty)
        let forbidden = ["AppKit", "SwiftUI", "Cocoa", "SwiftTerm", "KeyboardShortcuts"]

        for file in files {
            for line in try String(contentsOf: file, encoding: .utf8).split(separator: "\n") {
                let words = line.split(separator: " ")
                guard words.first == "import", words.count > 1 else { continue }
                let module = words[1].split(separator: ".").first.map(String.init) ?? ""
                XCTAssertFalse(forbidden.contains(module), "\(file.lastPathComponent) imports \(module)")
            }
        }
    }
}
