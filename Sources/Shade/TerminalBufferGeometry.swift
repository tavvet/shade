import SwiftTerm

/// Derives active-buffer geometry using only SwiftTerm's public API.
/// Buffer-relative positions are the coordinate space expected by
/// `SelectionService`; scroll-invariant rows additionally include the number
/// of lines already trimmed from the scrollback.
enum TerminalBufferGeometry {
    static func line(atBufferRow row: Int, in terminal: Terminal) -> BufferLine? {
        guard row >= 0 else { return nil }
        return terminal.getScrollInvariantLine(
            row: terminal.buffer.totalLinesTrimmed + row
        )
    }

    /// Highest existing row relative to the start of the active buffer.
    static func lastBufferRow(in terminal: Terminal) -> Int? {
        let firstInvariantRow = terminal.buffer.totalLinesTrimmed
        guard terminal.getScrollInvariantLine(row: firstInvariantRow) != nil else {
            return nil
        }

        // The active buffer is contiguous. Its capacity is the viewport plus
        // normal-buffer scrollback; the alternate buffer simply becomes an
        // earlier nil within the same search interval.
        var lower = 0
        var upper = max(1, terminal.rows + terminal.options.scrollback)
        while lower + 1 < upper {
            let candidate = lower + (upper - lower) / 2
            if terminal.getScrollInvariantLine(row: firstInvariantRow + candidate) != nil {
                lower = candidate
            } else {
                upper = candidate
            }
        }
        return lower
    }

    /// Cursor position relative to the start of the active buffer. SwiftTerm
    /// exposes the cursor relative to the terminal screen but keeps `yBase`
    /// private, so derive the screen base from the final buffer row.
    static func cursorBufferPosition(in terminal: Terminal) -> Position? {
        guard let lastRow = lastBufferRow(in: terminal) else { return nil }
        let cursor = terminal.getCursorLocation()
        let screenTop = max(0, lastRow - max(1, terminal.rows) + 1)
        return Position(
            col: min(max(cursor.x, 0), max(0, terminal.cols)),
            row: min(max(screenTop + cursor.y, 0), lastRow)
        )
    }

    static func scrollInvariantCursorPosition(in terminal: Terminal) -> Position? {
        guard let cursor = cursorBufferPosition(in: terminal) else { return nil }
        return Position(
            col: cursor.col,
            row: terminal.buffer.totalLinesTrimmed + cursor.row
        )
    }
}
