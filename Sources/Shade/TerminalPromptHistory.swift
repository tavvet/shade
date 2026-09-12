import Foundation
import SwiftTerm

/// Owns the OSC 133 history for one terminal: prompt marks, C→D command
/// timing, prompt navigation targets, and extraction of the last output.
/// UI and application side effects stay in `TerminalSession`.
struct TerminalPromptHistory {
    struct CommandCompletion: Equatable {
        let exitCode: Int?
        let duration: TimeInterval?
    }

    enum NavigationDirection {
        case previous
        case next
    }

    private(set) var marks: [PromptMark] = []
    private var commandStartedAt: Date?
    private var recordedColumns: Int?
    var isCommandRunning: Bool { commandStartedAt != nil }

    /// Coordinates cannot survive SwiftTerm's reflow. Command timing is
    /// independent of buffer geometry and must survive a resize or UI clear.
    mutating func invalidateCoordinates() {
        marks.removeAll()
    }

    /// Called synchronously for every view resize, including a resize back to
    /// the original width before the next OSC mark or history shortcut.
    mutating func terminalResized(columns: Int) {
        if let recordedColumns, recordedColumns != columns {
            invalidateCoordinates()
        }
        recordedColumns = columns
    }

    /// Records one OSC 133 payload. A completion is returned for every valid
    /// `D` mark; `duration` is nil when no preceding `C` mark was observed.
    mutating func record(
        payload: [UInt8],
        row: Int,
        in terminal: Terminal,
        now: Date = Date()
    ) -> CommandCompletion? {
        guard !terminal.isCurrentBufferAlternate else { return nil }
        guard let mark = PromptMark.parse(payload: payload[...], row: row) else { return nil }
        pruneStaleMarks(in: terminal)
        marks.append(mark)

        switch mark.kind {
        case .commandStart:
            commandStartedAt = now
            return nil
        case .commandDone(let exitCode):
            let duration = commandStartedAt.map { now.timeIntervalSince($0) }
            commandStartedAt = nil
            return CommandCompletion(exitCode: exitCode, duration: duration)
        case .promptStart, .promptEnd:
            // A fresh prompt/input without D abandons an unmatched C. Do not
            // later report the intervening idle time as a command duration.
            commandStartedAt = nil
            return nil
        }
    }

    /// Returns the viewport-relative row for the adjacent prompt. SwiftTerm's
    /// `scrollTo(row:)` performs the final clamp to the valid scrollback range.
    mutating func viewportRow(
        toward direction: NavigationDirection,
        in terminal: Terminal
    ) -> Int? {
        guard !terminal.isCurrentBufferAlternate else { return nil }
        pruneStaleMarks(in: terminal)
        let linesTop = terminal.buffer.totalLinesTrimmed
        let viewportTopInvariant = linesTop + terminal.buffer.yDisp
        let mark: PromptMark?
        switch direction {
        case .previous:
            mark = PromptMark.previousPromptStart(before: viewportTopInvariant, in: marks)
        case .next:
            mark = PromptMark.nextPromptStart(after: viewportTopInvariant, in: marks)
        }
        guard let mark else { return nil }

        return max(0, mark.row - linesTop)
    }

    /// Returns the most recently completed command's output without coupling
    /// history state to AppKit's pasteboard.
    mutating func lastCommandOutput(in terminal: Terminal) -> String? {
        guard !terminal.isCurrentBufferAlternate else { return nil }
        pruneStaleMarks(in: terminal)
        guard let range = PromptMark.lastCommandOutputRange(in: marks),
              let firstRow = range.first,
              let lastRow = range.last,
              let lastLine = terminal.getScrollInvariantLine(row: lastRow) else { return nil }

        // SwiftTerm's range extraction understands BufferLine.isWrapped: it
        // joins visual soft wraps but retains real line feeds. Prompt marks use
        // scroll-invariant rows, so translate them back into buffer indices.
        let linesTop = terminal.buffer.totalLinesTrimmed
        let text = terminal.getText(
            start: Position(col: 0, row: firstRow - linesTop),
            end: Position(col: lastLine.count, row: lastRow - linesTop)
        )
        return text.isEmpty ? nil : text
    }

    private mutating func pruneStaleMarks(in terminal: Terminal) {
        guard !terminal.isCurrentBufferAlternate else { return }
        terminalResized(columns: terminal.cols)
        marks.removeAll { terminal.getScrollInvariantLine(row: $0.row) == nil }
    }
}
