import SwiftTerm

@MainActor
extension TerminalView {
    /// Extends the in-buffer selection from the terminal cursor, or from the
    /// current selection endpoint when a selection is already active.
    func extendShadeKeyboardSelection(
        direction: PanelSelectionDirection,
        byWord: Bool
    ) {
        guard terminal.cols > 0,
              let lastRow = TerminalBufferGeometry.lastBufferRow(in: terminal) else {
            return
        }

        if !selection.active {
            guard let cursor = TerminalBufferGeometry.cursorBufferPosition(in: terminal) else {
                return
            }
            selection.setSoftStart(bufferPosition: cursor)
        }

        let destination = shadeKeyboardSelectionDestination(
            from: selection.end,
            direction: direction,
            byWord: byWord,
            lastRow: lastRow
        )
        selection.shiftExtend(bufferPosition: destination)
    }

    private func shadeKeyboardSelectionDestination(
        from start: Position,
        direction: PanelSelectionDirection,
        byWord: Bool,
        lastRow: Int
    ) -> Position {
        switch direction {
        case .left:
            return byWord
                ? shadeKeyboardWordPositionLeft(from: start, lastRow: lastRow)
                : previousShadeKeyboardCharacter(from: start, lastRow: lastRow)
        case .right:
            return byWord
                ? shadeKeyboardWordPositionRight(from: start, lastRow: lastRow)
                : nextShadeKeyboardCharacter(from: start, lastRow: lastRow)
        case .up:
            return shadeKeyboardVerticalPosition(from: start, rowDelta: -1, lastRow: lastRow)
        case .down:
            return shadeKeyboardVerticalPosition(from: start, rowDelta: 1, lastRow: lastRow)
        case .lineStart:
            return Position(col: 0, row: clampedShadeKeyboardRow(start.row, lastRow: lastRow))
        case .lineEnd:
            let row = clampedShadeKeyboardRow(start.row, lastRow: lastRow)
            let col = TerminalBufferGeometry.line(atBufferRow: row, in: terminal)?
                .getTrimmedLength() ?? 0
            return Position(col: col, row: row)
        }
    }

    private func previousShadeKeyboardCharacter(from start: Position, lastRow: Int) -> Position {
        var position = clampedShadeKeyboardPosition(start, lastRow: lastRow)
        if position.col == 0 {
            guard position.row > 0 else { return position }
            position.row -= 1
            position.col = terminal.cols
        }

        position.col -= 1
        guard let line = TerminalBufferGeometry.line(atBufferRow: position.row, in: terminal) else {
            return position
        }
        while position.col > 0, line.getWidth(index: position.col) == 0 {
            position.col -= 1
        }
        return position
    }

    private func nextShadeKeyboardCharacter(from start: Position, lastRow: Int) -> Position {
        var position = clampedShadeKeyboardPosition(start, lastRow: lastRow)
        if position.col >= terminal.cols {
            guard position.row < lastRow else { return position }
            return Position(col: 0, row: position.row + 1)
        }

        guard let line = TerminalBufferGeometry.line(atBufferRow: position.row, in: terminal) else {
            return position
        }
        while position.col > 0, line.getWidth(index: position.col) == 0 {
            position.col -= 1
        }
        position.col += max(1, line.getWidth(index: position.col))
        if position.col >= terminal.cols, position.row < lastRow {
            return Position(col: 0, row: position.row + 1)
        }
        position.col = min(position.col, terminal.cols)
        return position
    }

    private func shadeKeyboardVerticalPosition(
        from start: Position,
        rowDelta: Int,
        lastRow: Int
    ) -> Position {
        let position = clampedShadeKeyboardPosition(start, lastRow: lastRow)
        let row = min(max(position.row + rowDelta, 0), lastRow)
        var col = position.col
        if col < terminal.cols,
           let line = TerminalBufferGeometry.line(atBufferRow: row, in: terminal) {
            while col > 0, line.getWidth(index: col) == 0 {
                col -= 1
            }
        }
        return Position(col: col, row: row)
    }

    private func shadeKeyboardWordPositionLeft(from start: Position, lastRow: Int) -> Position {
        var position = previousShadeKeyboardCharacter(from: start, lastRow: lastRow)
        while !isShadeKeyboardWordCharacter(at: position) {
            let previous = previousShadeKeyboardCharacter(from: position, lastRow: lastRow)
            guard previous != position else { return position }
            position = previous
        }

        while true {
            let previous = previousShadeKeyboardCharacter(from: position, lastRow: lastRow)
            guard previous != position,
                  isShadeKeyboardWordCharacter(at: previous) else { return position }
            position = previous
        }
    }

    private func shadeKeyboardWordPositionRight(from start: Position, lastRow: Int) -> Position {
        var position = clampedShadeKeyboardPosition(start, lastRow: lastRow)

        while isShadeKeyboardWordCharacter(at: position) {
            let next = nextShadeKeyboardCharacter(from: position, lastRow: lastRow)
            guard next != position else { return position }
            position = next
            if next.row != start.row,
               TerminalBufferGeometry.line(atBufferRow: next.row, in: terminal)?.isWrapped != true {
                break
            }
        }
        while !isShadeKeyboardWordCharacter(at: position) {
            let next = nextShadeKeyboardCharacter(from: position, lastRow: lastRow)
            guard next != position else { return position }
            position = next
        }
        return position
    }

    private func isShadeKeyboardWordCharacter(at position: Position) -> Bool {
        guard position.row >= 0,
              position.col >= 0,
              position.col < terminal.cols,
              let line = TerminalBufferGeometry.line(atBufferRow: position.row, in: terminal),
              line.getWidth(index: position.col) > 0 else {
            return false
        }
        let character = terminal.getCharacter(for: line[position.col])
        return character.isLetter || character.isNumber || character == "_"
    }

    private func clampedShadeKeyboardPosition(_ position: Position, lastRow: Int) -> Position {
        Position(
            col: min(max(position.col, 0), terminal.cols),
            row: clampedShadeKeyboardRow(position.row, lastRow: lastRow)
        )
    }

    private func clampedShadeKeyboardRow(_ row: Int, lastRow: Int) -> Int {
        min(max(row, 0), lastRow)
    }
}
