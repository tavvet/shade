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
    /// UI and terminal frameworks stay in the app target. SwiftTerm and
    /// KeyboardShortcuts are also absent from ShadeCore's package dependencies;
    /// this check covers system frameworks the compiler would accept.
    private static let forbidden: Set<String> = [
        "AppKit", "SwiftUI", "Cocoa", "Carbon", "UIKit", "SwiftTerm", "KeyboardShortcuts",
    ]

    func testShadeCoreDoesNotImportUIOrTerminalFrameworks() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Sources/ShadeCore")
            .standardizedFileURL
        let files = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty)

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for module in Self.importedModules(in: source) where Self.forbidden.contains(module) {
                XCTFail("\(file.lastPathComponent) imports \(module)")
            }
        }
    }

    func testImportParserSeesAttributedAndDeclarationImports() {
        let source = """
        import Foundation
        @preconcurrency import AppKit
        @_exported   import SwiftUI
        @testable @preconcurrency import Cocoa
        import class AppKit.NSColor
        import struct Carbon.HIToolbox.EventHotKeyID
        import Carbon.HIToolbox
            import os
        // import UIKit
        let note = "import SwiftTerm"
        """

        XCTAssertEqual(Self.importedModules(in: source), [
            "Foundation", "AppKit", "SwiftUI", "Cocoa", "AppKit", "Carbon", "Carbon", "os",
        ])
    }

    /// Top-level module of every import declaration, including attributed
    /// (`@preconcurrency`, `@_exported`) and declaration (`import class M.T`)
    /// forms. Comments and string contents are not declarations.
    static func importedModules(in source: String) -> [String] {
        let pattern = #"^\s*(?:@\w+(?:\([^)]*\))?\s+)*import\s+(?:(?:typealias|struct|class|enum|protocol|let|var|func)\s+)?([A-Za-z_][A-Za-z0-9_]*)"#
        let regex = try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        let range = NSRange(source.startIndex..., in: source)
        return regex.matches(in: source, range: range).compactMap { match in
            Range(match.range(at: 1), in: source).map { String(source[$0]) }
        }
    }
}
