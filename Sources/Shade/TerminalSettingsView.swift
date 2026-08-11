import SwiftUI

struct TerminalSettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("Shell Integration") {
                Toggle("Enrich completion inside Shade (zsh)", isOn: $model.preferences.shellEnrichment)
                Text("Turns on tab-completion for git, make, ssh, … in new zsh tabs "
                     + "without modifying your shell files. No effect if your shell "
                     + "already sets up completion (oh-my-zsh, etc.).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Cursor") {
                Picker("Shape", selection: $model.preferences.cursorShape) {
                    Text("Block").tag(Preferences.CursorShape.block)
                    Text("Bar").tag(Preferences.CursorShape.bar)
                    Text("Underline").tag(Preferences.CursorShape.underline)
                }
                .pickerStyle(.segmented)
                Toggle("Blink cursor", isOn: $model.preferences.cursorBlink)
            }

            Section("Feedback") {
                Toggle("Visual bell (flash on bell)", isOn: $model.preferences.visualBell)
            }
        }
        .formStyle(.grouped)
    }
}
