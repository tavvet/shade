import SwiftUI

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
            Section("Typography") {
                Picker("Font", selection: $model.fontName) {
                    ForEach(fontChoices, id: \.value) { choice in
                        Text(choice.label).tag(choice.value)
                    }
                }

                HStack {
                    Text("Size")
                        .frame(width: 76, alignment: .leading)
                    Slider(value: $model.fontSize, in: 9...22, step: 1)
                    Text("\(Int(model.fontSize)) pt")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Color & Background") {
                HStack {
                    Text("Opacity")
                        .frame(width: 76, alignment: .leading)
                    Slider(value: $model.backgroundOpacity, in: 0.3...1.0, step: 0.05)
                    Text("\(Int((model.backgroundOpacity * 100).rounded()))%")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                        .foregroundStyle(.secondary)
                }

                ColorPicker(
                    "Link highlight",
                    selection: $model.linkHighlightColor,
                    supportsOpacity: false
                )

                Toggle("Background blur", isOn: $model.backgroundBlur)
                if model.backgroundBlur {
                    Picker("Blur material", selection: $model.blurMaterial) {
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
