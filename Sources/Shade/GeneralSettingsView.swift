import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("Panel Size") {
                fractionRow(title: "Width", value: $model.widthFraction)
                fractionRow(title: "Height", value: $model.heightFraction)
            }

            Section("Position") {
                Picker("Horizontal", selection: $model.horizontalAlignment) {
                    Text("Left").tag(Preferences.HorizontalAlignment.left)
                    Text("Center").tag(Preferences.HorizontalAlignment.center)
                    Text("Right").tag(Preferences.HorizontalAlignment.right)
                }
                .pickerStyle(.segmented)

                Picker("Display", selection: $model.screenChoice) {
                    Text("Main").tag(Preferences.ScreenChoice.main)
                    Text("Under pointer").tag(Preferences.ScreenChoice.mouseLocation)
                }
                .pickerStyle(.segmented)
            }

            Section("Behavior") {
                Toggle("Hide when Shade loses focus", isOn: $model.hideOnFocusLoss)
                Toggle("New tab uses the current directory", isOn: $model.newTabInheritsCwd)
            }

            Section("Startup") {
                Toggle("Open at Login", isOn: $model.openAtLogin)
            }

            Section("Animation") {
                HStack {
                    Text("Slide")
                        .frame(width: 76, alignment: .leading)
                    Slider(value: $model.animationDuration, in: 0.0...0.5, step: 0.02)
                    Text("\(Int((model.animationDuration * 1000).rounded())) ms")
                        .monospacedDigit()
                        .frame(width: 56, alignment: .trailing)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func fractionRow(title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
                .frame(width: 76, alignment: .leading)
            Slider(value: value, in: 0.1...1.0, step: 0.05)
            Text("\(Int((value.wrappedValue * 100).rounded()))%")
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
    }
}
