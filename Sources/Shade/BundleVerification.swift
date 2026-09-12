import Foundation
import KeyboardShortcuts

/// Build-time smoke check. It runs before application setup and never starts a
/// terminal, registers a hotkey, activates the app or writes user preferences.
@MainActor
enum BundleVerification {
    static func run() -> Bool {
        guard let resources = Bundle.main.resourceURL,
              let shortcuts = Bundle(url: resources.appendingPathComponent(
                  "KeyboardShortcuts_KeyboardShortcuts.bundle"
              )),
              let terminal = Bundle(url: resources.appendingPathComponent(
                  "SwiftTerm_SwiftTerm.bundle"
              )),
              let shader = terminal.url(forResource: "Shaders", withExtension: "metal"),
              let shaderData = try? Data(contentsOf: shader),
              !shaderData.isEmpty else {
            return fail("Required SwiftPM resources are missing or unreadable")
        }

        let localizedSpace = shortcuts.localizedString(forKey: "space_key", value: nil, table: nil)
        guard localizedSpace != "space_key",
              KeyboardShortcuts.Shortcut(.space).description == localizedSpace.capitalized else {
            return fail("KeyboardShortcuts could not load its packaged localization")
        }
        return true
    }

    private static func fail(_ message: String) -> Bool {
        FileHandle.standardError.write(Data("error: \(message)\n".utf8))
        return false
    }
}
