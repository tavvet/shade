import SwiftUI
import ShadeCore

struct AppearanceSettingsView: View {
    @ObservedObject var model: SettingsModel

    private let fontChoices: [(label: String, value: String)] = [
        ("System Monospace", ""),
        ("Menlo", "Menlo"),
        ("Monaco", "Monaco"),
        ("SF Mono", "SF Mono"),
        ("Courier New", "Courier New"),
    ]

    var body: some View {
        Form {
            Section("Interface") {
                Toggle(
                    "Show current input source in tab bar",
                    isOn: $model.preferences.showInputSourceIndicator
                )

                Text("Displays the active keyboard input source next to the new-tab button.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Minimum tab width")
                    Slider(
                        value: $model.preferences.tabMinimumWidth,
                        in: Preferences.minTabWidth...Preferences.maxTabWidth,
                        step: 10
                    )
                    Text("\(Int(model.preferences.tabMinimumWidth)) pt")
                        .monospacedDigit()
                        .frame(width: 52, alignment: .trailing)
                        .foregroundStyle(.secondary)
                }

                Text("Keeps tabs with short titles easy to click.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Typography") {
                Picker("Font", selection: $model.preferences.fontName) {
                    ForEach(fontChoices, id: \.value) { choice in
                        Text(choice.label).tag(choice.value)
                    }
                }

                HStack {
                    Text("Size")
                        .frame(width: 76, alignment: .leading)
                    Slider(value: $model.preferences.fontSize, in: 9...22, step: 1)
                    Text("\(Int(model.preferences.fontSize)) pt")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Color & Background") {
                ColorPicker(
                    "Text",
                    selection: model.terminalForegroundColor,
                    supportsOpacity: false
                )

                ColorPicker(
                    "Background",
                    selection: model.terminalBackgroundColor,
                    supportsOpacity: false
                )

                HStack {
                    Text("Opacity")
                        .frame(width: 76, alignment: .leading)
                    Slider(value: $model.preferences.backgroundOpacity, in: 0.3...1.0, step: 0.05)
                    Text("\(Int((model.preferences.backgroundOpacity * 100).rounded()))%")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                        .foregroundStyle(.secondary)
                }

                ColorPicker(
                    "Link highlight",
                    selection: model.linkHighlightColor,
                    supportsOpacity: false
                )

                Toggle("Background blur", isOn: $model.preferences.backgroundBlur)
                if model.preferences.backgroundBlur {
                    Picker("Blur material", selection: $model.preferences.blurMaterial) {
                        Text("HUD").tag(Preferences.BlurMaterial.hud)
                        Text("Under window").tag(Preferences.BlurMaterial.underWindow)
                        Text("Sidebar").tag(Preferences.BlurMaterial.sidebar)
                        Text("Full screen").tag(Preferences.BlurMaterial.fullScreen)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
