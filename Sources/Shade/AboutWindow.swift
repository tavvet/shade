import AppKit
import SwiftUI

struct AboutView: View {
    static let repositoryURL    = URL(string: "https://github.com/tavvet/shade")!
    static let licenseURL       = URL(string: "https://github.com/tavvet/shade/blob/main/LICENSE")!
    static let thirdpartyURL    = URL(string: "https://github.com/tavvet/shade/blob/main/THIRDPARTY.md")!

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    var body: some View {
        VStack(spacing: 14) {
            iconImage
                .resizable()
                .interpolation(.high)
                .frame(width: 96, height: 96)

            VStack(spacing: 4) {
                Text("Shade")
                    .font(.title2.weight(.semibold))
                Text("Drop-down terminal for macOS")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Version \(version) (\(build))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
                Link("Repository",       destination: Self.repositoryURL)
                Link("License",          destination: Self.licenseURL)
                Link("Acknowledgements", destination: Self.thirdpartyURL)
            }
            .font(.callout)

            Text("MIT licensed — © 2026 Anton Rudakov")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .fixedSize()
    }

    private var iconImage: Image {
        if let icon = NSApp.applicationIconImage {
            return Image(nsImage: icon)
        }
        return Image(systemName: "terminal.fill")
    }
}

@MainActor
final class AboutWindowController: NSWindowController {
    init() {
        let hosting = NSHostingController(rootView: AboutView())
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable]
        window.title = "About Shade"
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("AboutWindowController is not Storyboard-loadable") }

    func present() {
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
