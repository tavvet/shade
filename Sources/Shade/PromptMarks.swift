import Foundation

/// OSC 133 prompt-mark record. Final Term / iTerm2 spec:
///   ESC ] 133 ; A ST       — prompt start
///   ESC ] 133 ; B ST       — prompt end (command input begins)
///   ESC ] 133 ; C ST       — pre-execution (command output begins)
///   ESC ] 133 ; D [;exit] ST — command finished
/// The row is stored in scroll-invariant coordinates so the mark remains
/// addressable after the buffer rotates old lines out of scrollback.
struct PromptMark: Equatable {
    enum Kind: Equatable {
        case promptStart
        case promptEnd
        case commandStart
        case commandDone(exitCode: Int?)
    }
    let kind: Kind
    let row: Int

    /// Parse a single OSC 133 payload — the bytes between `OSC 133 ;` and
    /// the terminator. First semicolon-separated token must be `A`/`B`/`C`/`D`;
    /// for `D` the next numeric token, if present, is the exit code. Any
    /// further tokens (e.g. `;P;aid=…` per spec) are accepted but ignored.
    static func parse(payload: ArraySlice<UInt8>, row: Int) -> PromptMark? {
        guard !payload.isEmpty,
              let text = String(bytes: payload, encoding: .utf8) else { return nil }
        let parts = text.split(separator: ";", omittingEmptySubsequences: false)
        guard let first = parts.first, first.count == 1 else { return nil }
        switch first {
        case "A": return PromptMark(kind: .promptStart, row: row)
        case "B": return PromptMark(kind: .promptEnd, row: row)
        case "C": return PromptMark(kind: .commandStart, row: row)
        case "D":
            let exit = parts.count >= 2 ? Int(parts[1]) : nil
            return PromptMark(kind: .commandDone(exitCode: exit), row: row)
        default:
            return nil
        }
    }
}

extension PromptMark {
    /// Highest-row `.promptStart` mark with `row < cutoff`. Returns nil if no
    /// such mark exists. Uses min/max rather than array order — a `clear`
    /// command (CSI 2J + cursor home) can record new marks at lower row
    /// numbers than older entries, so chronological order isn't always
    /// row-sorted.
    static func previousPromptStart(before cutoff: Int, in marks: [PromptMark]) -> PromptMark? {
        marks
            .filter { mark in
                guard case .promptStart = mark.kind else { return false }
                return mark.row < cutoff
            }
            .max(by: { $0.row < $1.row })
    }

    /// Lowest-row `.promptStart` mark with `row > cutoff`. Returns nil if no
    /// such mark exists.
    static func nextPromptStart(after cutoff: Int, in marks: [PromptMark]) -> PromptMark? {
        marks
            .filter { mark in
                guard case .promptStart = mark.kind else { return false }
                return mark.row > cutoff
            }
            .min(by: { $0.row < $1.row })
    }

    /// Row range covering the output of the most recently completed
    /// command, in scroll-invariant coordinates. Convention follows the
    /// Final Term spec: `C` is emitted at the start of the output area,
    /// `D` just before the next prompt — so output lives in
    /// `[C.row, D.row)`. Matching is chronological (by array index, not
    /// by row), so a `clear` command between two C/D pairs doesn't
    /// confuse the picker. Returns nil if there's no completed pair or
    /// the command produced no output (C.row == D.row).
    static func lastCommandOutputRange(in marks: [PromptMark]) -> Range<Int>? {
        guard let dIndex = marks.lastIndex(where: { mark in
            if case .commandDone = mark.kind { return true }
            return false
        }) else { return nil }
        let d = marks[dIndex]
        let preceding = marks[0..<dIndex]
        guard let cIndex = preceding.lastIndex(where: { mark in
            if case .commandStart = mark.kind { return true }
            return false
        }) else { return nil }
        let c = marks[cIndex]
        guard c.row < d.row else { return nil }
        return c.row..<d.row
    }
}
