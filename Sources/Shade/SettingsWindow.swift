import AppKit
import SwiftUI

@MainActor
final class SettingsModel: ObservableObject {
    @Published var widthFraction: Double { didSet { save() } }
    @Published var heightFraction: Double { didSet { save() } }
    @Published var horizontalAlignment: Preferences.HorizontalAlignment { didSet { save() } }
    @Published var screenChoice: Preferences.ScreenChoice { didSet { save() } }

    init() {
        let prefs = Preferences.load()
        widthFraction = Double(prefs.widthFraction)
        heightFraction = Double(prefs.heightFraction)
        horizontalAlignment = prefs.horizontalAlignment
        screenChoice = prefs.screenChoice
    }

    private func save() {
        let store = UserDefaults.standard
        store.set(widthFraction, forKey: "widthFraction")
        store.set(heightFraction, forKey: "heightFraction")
        store.set(horizontalAlignment.rawValue, forKey: "horizontalAlignment")
        store.set(screenChoice.rawValue, forKey: "screenChoice")
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("Size") {
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

                Picker("Screen", selection: $model.screenChoice) {
                    Text("Main").tag(Preferences.ScreenChoice.main)
                    Text("Under mouse").tag(Preferences.ScreenChoice.mouseLocation)
                }
                .pickerStyle(.segmented)
            }
            Section {
                Text("Changes apply on next F12.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 360, minHeight: 280)
    }

    @ViewBuilder
    private func fractionRow(title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
                .frame(width: 56, alignment: .leading)
            Slider(value: value, in: 0.1...1.0, step: 0.05)
            Text("\(Int((value.wrappedValue * 100).rounded()))%")
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    private let model = SettingsModel()

    init() {
        let hosting = NSHostingController(rootView: SettingsView(model: model))
        hosting.preferredContentSize = NSSize(width: 380, height: 320)
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable]
        window.title = "Shade Settings"
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 380, height: 320))
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("SettingsWindowController is not Storyboard-loadable") }

    func present() {
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
