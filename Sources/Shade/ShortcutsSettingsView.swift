import KeyboardShortcuts
import SwiftUI

struct ShortcutsSettingsView: View {
    private struct Row: Identifiable {
        let action: String
        let keys: String
        var id: String { action }
    }

    private let rows: [Row] = [
        .init(action: "Toggle panel",       keys: "set above (default F12)"),
        .init(action: "Hide panel",         keys: "Esc"),
        .init(action: "New tab",            keys: "⌘T"),
        .init(action: "Close tab",          keys: "⌘W"),
        .init(action: "Switch to tab N",    keys: "⌘1 – ⌘9"),
        .init(action: "Connection picker",  keys: "⌘⇧P"),
        .init(action: "Connect profile N",  keys: "⌘⇧1 – ⌘⇧9"),
        .init(action: "Next tab",           keys: "⌃Tab"),
        .init(action: "Previous tab",       keys: "⌃⇧Tab"),
        .init(action: "Copy / Paste",       keys: "⌘C / ⌘V"),
        .init(action: "Cut from input",     keys: "⌘X (best-effort, see README)"),
        .init(action: "Select all",         keys: "⌘A"),
        .init(action: "Clear (prompt → bottom)", keys: "⌘K"),
        .init(action: "Delete word back",   keys: "⌥⌫"),
        .init(action: "Beginning / end of line", keys: "Home / End"),
        .init(action: "Extend selection",   keys: "⇧← ⇧→ ⇧↑ ⇧↓"),
        .init(action: "  by word",          keys: "⌥⇧← / ⌥⇧→"),
        .init(action: "  to line edges",    keys: "⌘⇧← / ⌘⇧→"),
        .init(action: "Open link / file",   keys: "⌘-click"),
        .init(action: "Settings",           keys: "⌘,"),
        .init(action: "Quit",               keys: "⌘Q"),
    ]

    var body: some View {
        Form {
            Section("Global Hotkey") {
                KeyboardShortcuts.Recorder("Toggle Shade", name: .toggleShade)
            }

            Section("Keyboard Reference") {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        HStack(spacing: 16) {
                            Text(row.action)
                            Spacer()
                            Text(row.keys)
                                .foregroundStyle(.secondary)
                                .monospaced()
                                .multilineTextAlignment(.trailing)
                        }
                        .padding(.vertical, 6)
                        if index < rows.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
