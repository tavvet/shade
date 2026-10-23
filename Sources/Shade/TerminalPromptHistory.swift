import Foundation
import SwiftTerm

/// Owns prompt coordinates and command timing using copied SwiftTerm values.
struct TerminalPromptHistory {
    struct CommandCompletion: Equatable {
        let exitCode: Int?
        let duration: TimeInterval?
    }

    enum NavigationDirection { case previous, next }

    private(set) var marks: [PromptMark] = []
    private var commandStartedAt: Date?
    private var recordedColumns: Int?
    private var geometryGeneration: UInt64?
    var isCommandRunning: Bool { commandStartedAt != nil }

    mutating func invalidateCoordinates() { marks.removeAll() }

    mutating func terminalResized(columns: Int) {
        if let recordedColumns, recordedColumns != columns { invalidateCoordinates() }
        recordedColumns = columns
    }

    /// Events retain their parser-time geometry even if a later byte switches
    /// buffers. Stale coordinates are discarded without losing command timing.
    mutating func record(
        event: TerminalOscEvent,
        currentState: TerminalInputStateSnapshot,
        now: Date? = nil
    ) -> CommandCompletion? {
        guard let context = event.context, !context.isAlternateBuffer,
              let mark = PromptMark.parse(payload: event.payload[...], row: context.bufferCursor.row)
        else { return nil }
        synchronizeGeometry(currentState)
        if context.geometryGeneration == currentState.geometryGeneration {
            marks.removeAll { $0.row < context.firstRetainedRow }
            marks.append(mark)
        }
        let time = now ?? context.timestamp.map(Date.init(timeIntervalSinceReferenceDate:)) ?? Date()
        switch mark.kind {
        case .commandStart:
            commandStartedAt = time
            return nil
        case .commandDone(let exitCode):
            let duration = commandStartedAt.map { time.timeIntervalSince($0) }
            commandStartedAt = nil
            return CommandCompletion(exitCode: exitCode, duration: duration)
        case .promptStart, .promptEnd:
            commandStartedAt = nil
            return nil
        }
    }

    mutating func viewportRow(
        toward direction: NavigationDirection,
        in snapshot: TerminalContentSnapshot,
        viewportRow: Int
    ) -> Int? {
        guard !snapshot.inputState.isAlternateBuffer else { return nil }
        pruneStaleMarks(in: snapshot)
        let firstRow = snapshot.capturedRange.lowerBound
        let viewportTop = firstRow + viewportRow
        let mark: PromptMark?
        switch direction {
        case .previous:
            mark = PromptMark.previousPromptStart(before: viewportTop, in: marks)
        case .next:
            mark = PromptMark.nextPromptStart(after: viewportTop, in: marks)
        }
        return mark.map { max(0, $0.row - firstRow) }
    }

    mutating func lastCommandOutput(in snapshot: TerminalContentSnapshot) -> String? {
        guard !snapshot.inputState.isAlternateBuffer else { return nil }
        pruneStaleMarks(in: snapshot)
        guard let range = PromptMark.lastCommandOutputRange(in: marks),
              let first = range.first, let last = range.last,
              snapshot.capturedRange.contains(first), snapshot.capturedRange.contains(last)
        else { return nil }
        let rows = snapshot.rows.filter { range.contains($0.absoluteRow) }
        var text = ""
        for (index, row) in rows.enumerated() {
            if index > 0, !row.isWrapped { text += "\n" }
            text += row.text
        }
        // Match SwiftTerm's selection extraction: omit trailing blank rows.
        while text.last == "\n" { text.removeLast() }
        return text.isEmpty ? nil : text
    }

    private mutating func synchronizeGeometry(_ state: TerminalInputStateSnapshot) {
        if let geometryGeneration, geometryGeneration != state.geometryGeneration {
            invalidateCoordinates()
        }
        geometryGeneration = state.geometryGeneration
        terminalResized(columns: state.dimensions.cols)
    }

    private mutating func pruneStaleMarks(in snapshot: TerminalContentSnapshot) {
        synchronizeGeometry(snapshot.inputState)
        marks.removeAll { !snapshot.capturedRange.contains($0.row) }
    }
}
