import SwiftTerm

@MainActor
extension TerminalView {
    func extendShadeKeyboardSelection(direction: PanelSelectionDirection, byWord: Bool) {
        let movement: TerminalSelectionDirection
        switch direction {
        case .left: movement = .left
        case .right: movement = .right
        case .up: movement = .up
        case .down: movement = .down
        case .lineStart: movement = .lineStart
        case .lineEnd: movement = .lineEnd
        }
        extendSelection(direction: movement, byWord: byWord)
    }
}
