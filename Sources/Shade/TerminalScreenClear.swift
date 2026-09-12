import SwiftTerm

/// Clears text above the current logical line without sending PTY input or
/// moving the cursor out of sync with the shell's line editor.
/// Inline images and line rendering modes stay intact: SwiftTerm does not expose
/// a public per-line reset for them, and feeding local escapes could interrupt a
/// partially received PTY escape sequence.
enum TerminalScreenClear {
    @discardableResult
    static func clearPreviousOutput(in terminal: Terminal, preservePrompt: Bool = true) -> Bool {
        guard !terminal.isCurrentBufferAlternate,
              let cursor = TerminalBufferGeometry.cursorBufferPosition(in: terminal) else {
            return false
        }
        let screenTop = cursor.row - terminal.getCursorLocation().y
        var firstPreservedRow = cursor.row
        while firstPreservedRow > screenTop,
              terminal.bufferLine(atRow: firstPreservedRow)?.isWrapped == true {
            firstPreservedRow -= 1
        }
        // OSC 133 also identifies hard line breaks in a multi-line prompt/input.
        if preservePrompt,
           let prompt = terminal.activeSemanticPromptOrigin, prompt.row <= cursor.row {
            firstPreservedRow = max(screenTop, min(firstPreservedRow, prompt.row))
        }
        guard screenTop < firstPreservedRow else { return false }

        let blank = BufferLine(cols: terminal.cols)
        for row in screenTop..<firstPreservedRow {
            terminal.bufferLine(atRow: row)?.copyFrom(line: blank)
        }
        terminal.updateFullScreen()
        return true
    }
}
