import AppKit
import SwiftUI

struct AboutView: View {
    static let repositoryURL    = URL(string: "https://github.com/tavvet/shade")!
    static let licenseURL       = URL(string: "https://github.com/tavvet/shade/blob/main/LICENSE")!
    static let thirdpartyURL    = URL(string: "https://github.com/tavvet/shade/blob/main/THIRDPARTY.md")!
    static let supportURL       = URL(string: "https://github.com/tavvet/shade#support")!

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
                Link("Support",          destination: Self.supportURL)
            }
            .font(.callout)

            VStack(spacing: 6) {
                Text("Donate (USDT) — copy and paste:")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                AddressRow(label: "BEP-20", address: "0x9fbaa332ef68433d17c350d085bc5a4b404ec495")
                AddressRow(label: "TRC-20", address: "TT8jU9Tbw5iLrNANTnCZgFCnCp6ZhAe2xm")
                AddressRow(label: "SPL",    address: "4sGwS8KgVanzCUeMNnWXBHwxv6voCKY7TmPkWRhdt2pR")
            }

            Text("MIT licensed — © 2026 Anton Rudakov")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .fixedSize()
    }

    private struct AddressRow: View {
        let label: String
        let address: String
        @State private var justCopied = false

        var body: some View {
            HStack(spacing: 8) {
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .trailing)
                Text(address)
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
                Button(action: copy) {
                    Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .help("Copy address")
            }
        }

        private func copy() {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(address, forType: .string)
            justCopied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                justCopied = false
            }
        }
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
