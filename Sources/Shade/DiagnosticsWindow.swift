import AppKit
import SwiftUI
import KeyboardShortcuts

/// Diagnostics window — a read-only snapshot of what Shade currently sees
/// (app version, macOS version, screens, hotkey, active session state).
/// Designed to be copy-paste-ready for GitHub issue bodies.
struct DiagnosticsView: View {
    let report: String
    @State private var justCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Diagnostics")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button(action: copy) {
                    Label(justCopied ? "Copied" : "Copy", systemImage: justCopied ? "checkmark" : "doc.on.doc")
                        .font(.callout)
                }
                .buttonStyle(.borderedProminent)
                .help("Copy the full report to the clipboard")
            }

            Text("Paste this into a bug report — it covers most of the questions a maintainer would ask first.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                Text(report)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            }
            .frame(minHeight: 280)
        }
        .padding(20)
        .frame(width: 520)
    }

    private func copy() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(report, forType: .string)
        justCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            justCopied = false
        }
    }
}

@MainActor
final class DiagnosticsWindowController: NSWindowController {
    private let terminals: TerminalsController

    init(terminals: TerminalsController) {
        self.terminals = terminals
        // Placeholder window — the real view is installed in `present()` so the
        // report reflects state at the moment of opening, not at app launch.
        let window = NSWindow(contentRect: .zero,
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "Shade Diagnostics"
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("DiagnosticsWindowController is not Storyboard-loadable")
    }

    func present() {
        let report = DiagnosticsReport.build(terminals: terminals)
        let hosting = NSHostingController(rootView: DiagnosticsView(report: report))
        window?.contentViewController = hosting
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Builds the markdown-ish text rendered in the Diagnostics window.
/// Pulls from `Bundle.main`, `ProcessInfo`, `NSScreen`, `KeyboardShortcuts`,
/// and the active `TerminalSession`. Anything the user couldn't reasonably
/// look up themselves and would be asked for in an issue should land here.
enum DiagnosticsReport {
    @MainActor
    static func build(terminals: TerminalsController) -> String {
        var lines: [String] = []
        lines.append("**Shade diagnostics**")
        lines.append("")
        lines.append(appLine())
        lines.append(systemLine())
        lines.append(screensLine())
        lines.append(hotkeyLine())
        lines.append("")
        lines.append("Active session:")
        if let session = terminals.activeSession {
            lines.append(contentsOf: sessionLines(session))
        } else {
            lines.append("  (none)")
        }
        lines.append("")
        lines.append("Sessions: \(terminals.sessions.count) total")
        return lines.joined(separator: "\n")
    }

    private static func appLine() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build   = info?["CFBundleVersion"] as? String ?? "?"
        return "App:        \(version) (build \(build))"
    }

    private static func systemLine() -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        #if arch(arm64)
        let arch = "arm64"
        #elseif arch(x86_64)
        let arch = "x86_64"
        #else
        let arch = "unknown"
        #endif
        return "OS:         macOS \(os) [\(arch)]"
    }

    @MainActor
    private static func screensLine() -> String {
        let screens = NSScreen.screens
        let prefix = "Screens:    "
        let indent = String(repeating: " ", count: prefix.count)
        let descriptions = screens.enumerated().map { i, s -> String in
            let f = s.frame
            let mark = (s == NSScreen.main) ? "*" : " "
            return "\(mark)#\(i + 1) \(Int(f.width))×\(Int(f.height)) @ \(Int(f.minX)),\(Int(f.minY))"
        }
        guard let first = descriptions.first else { return prefix + "(none)" }
        let rest = descriptions.dropFirst().map { indent + $0 }
        return ([prefix + first] + rest).joined(separator: "\n")
    }

    @MainActor
    private static func hotkeyLine() -> String {
        let binding = KeyboardShortcuts.getShortcut(for: .toggleShade)?.description ?? "(unbound)"
        return "Hotkey:     \(binding)"
    }

    @MainActor
    private static func sessionLines(_ session: TerminalSession) -> [String] {
        let shellEnv = ProcessInfo.processInfo.environment["SHELL"] ?? "(unset)"
        let cwd = session.cwd.isEmpty ? "(none)" : session.cwd
        let branch = session.branch.isEmpty ? "(none)" : session.branch
        let remote = session.remoteIndicator ?? "(none)"
        let status: String
        if let s = session.gitStatus {
            if s == .empty {
                status = "clean"
            } else {
                status = "±\(s.filesChanged) +\(s.insertions) -\(s.deletions)"
            }
        } else {
            status = "(no repo)"
        }
        let promptMarkCount = session.promptMarks.count
        let osc133 = promptMarkCount > 0
            ? "active (\(promptMarkCount) marks recorded)"
            : "not detected (shell snippet not sourced?)"
        return [
            "  Shell:    \(shellEnv) — bundle saw `\(session.shellName)`",
            "  CWD:      \(cwd)",
            "  Branch:   \(branch)",
            "  Status:   \(status)",
            "  Remote:   \(remote)",
            "  OSC 133:  \(osc133)",
        ]
    }
}
