import AppKit

enum SSHConnectionPickerSelectionDirection: Equatable {
    case up
    case down
}

enum SSHConnectionPickerKeyNavigation {
    private static let modifiedArrowFlags: NSEvent.ModifierFlags = [
        .command,
        .control,
        .option,
        .shift,
    ]

    static func direction(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        hasMarkedText: Bool
    ) -> SSHConnectionPickerSelectionDirection? {
        guard !hasMarkedText else { return nil }
        guard modifierFlags.intersection(modifiedArrowFlags).isEmpty else {
            return nil
        }

        switch keyCode {
        case KeyCodes.upArrow:
            return .up
        case KeyCodes.downArrow:
            return .down
        default:
            return nil
        }
    }
}

enum SSHConnectionPickerSelection {
    static func movedID<ID: Equatable>(
        in ids: [ID],
        from selectedID: ID?,
        direction: SSHConnectionPickerSelectionDirection
    ) -> ID? {
        guard !ids.isEmpty else { return nil }
        guard let selectedID, let currentIndex = ids.firstIndex(of: selectedID) else {
            return direction == .down ? ids.first : ids.last
        }

        let offset = direction == .down ? 1 : -1
        let destinationIndex = min(max(0, currentIndex + offset), ids.count - 1)
        return ids[destinationIndex]
    }
}
