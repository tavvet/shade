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

    /// Records one OSC 133 payload. A completion is returned for every valid
    /// `D` mark; `duration` is nil when no preceding `C` mark was observed.
    mutating func record(
        payload: [UInt8],
        row: Int,
        in terminal: Terminal,
        now: Date = Date()
    ) -> CommandCompletion? {
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
        default:
            return nil
        }
    }

    /// Returns the viewport-relative row for the adjacent prompt, clamped to
    /// SwiftTerm's valid scrollback range.
    mutating func viewportRow(
        toward direction: NavigationDirection,
        in terminal: Terminal
    ) -> Int? {
        pruneStaleMarks(in: terminal)
        let viewportTopInvariant = terminal.scrollInvariantLinesTop + terminal.buffer.yDisp
        let mark: PromptMark?
        switch direction {
        case .previous:
            mark = PromptMark.previousPromptStart(before: viewportTopInvariant, in: marks)
        case .next:
            mark = PromptMark.nextPromptStart(after: viewportTopInvariant, in: marks)
        }
        guard let mark else { return nil }

        let rawViewportRow = mark.row - terminal.scrollInvariantLinesTop
        return max(0, min(rawViewportRow, terminal.maxScrollbackRow))
    }

    /// Returns the most recently completed command's output without coupling
    /// history state to AppKit's pasteboard.
    mutating func lastCommandOutput(in terminal: Terminal) -> String? {
        pruneStaleMarks(in: terminal)
        guard let range = PromptMark.lastCommandOutputRange(in: marks) else { return nil }
        let lines = range.compactMap { row in
            terminal.getScrollInvariantLine(row: row)?.translateToString(trimRight: true)
        }
        let text = lines.joined(separator: "\n")
        return text.isEmpty ? nil : text
    }

    private mutating func pruneStaleMarks(in terminal: Terminal) {
        marks.removeAll { terminal.getScrollInvariantLine(row: $0.row) == nil }
    }
}
