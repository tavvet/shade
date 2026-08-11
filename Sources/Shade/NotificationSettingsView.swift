import SwiftUI

struct NotificationSettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("Command Completion") {
                Toggle(
                    "Notify when a command finishes while hidden",
                    isOn: $model.preferences.notifyOnCommandFinish
                )
                if model.preferences.notifyOnCommandFinish {
                    HStack {
                        Text("After")
                            .frame(width: 76, alignment: .leading)
                        Slider(value: $model.preferences.notifyThresholdSeconds, in: 5...300, step: 5)
                        Text("\(Int(model.preferences.notifyThresholdSeconds)) s")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                            .foregroundStyle(.secondary)
                    }
                    Label(
                        "Requires OSC 133 shell integration; see the README for setup.",
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
