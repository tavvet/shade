import AppKit

/// Reads the click count of the left mouse event being handled, such as
/// `NSApp.currentEvent` inside a SwiftUI tap gesture or button action.
enum ClickEvent {
    /// The second click of a double-click.
    static func isDoubleClick(_ event: NSEvent?) -> Bool {
        clickCount(of: event) == 2
    }

    /// Any click after the first one of a double- or triple-click.
    static func isRepeatedClick(_ event: NSEvent?) -> Bool {
        (clickCount(of: event) ?? 0) >= 2
    }

    private static func clickCount(of event: NSEvent?) -> Int? {
        guard let event,
              event.type == .leftMouseDown || event.type == .leftMouseUp else {
            return nil
        }
        return event.clickCount
    }
}
