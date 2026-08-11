import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let model = SettingsModel()

    init() {
        let hosting = NSHostingController(rootView: SettingsView(model: model))
        hosting.preferredContentSize = NSSize(width: 800, height: 580)
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .resizable]
        window.title = "Shade Settings"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 720, height: 500)
        window.setContentSize(NSSize(width: 800, height: 580))
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("SettingsWindowController is not Storyboard-loadable") }

    func present() {
        model.reloadPreferences()
        // Switch from .accessory to .regular while the Settings window is open so that
        // system panels (notably NSColorPanel used by SwiftUI's ColorPicker) actually
        // open — they refuse to show for LSUIElement / .accessory apps.
        NSApp.setActivationPolicy(.regular)
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        positionColorPanelNearSettings()
    }

    /// Without nudging it, NSColorPanel opens in the bottom-left of the active screen
    /// the first time it's used. Position it next to the Settings window instead.
    private func positionColorPanelNearSettings() {
        let panel = NSColorPanel.shared   // touching `.shared` creates the panel if needed
        guard let settingsFrame = window?.frame, let screen = NSScreen.main else {
            panel.center()
            return
        }
        let panelSize = panel.frame.size
        var origin = NSPoint(
            x: settingsFrame.maxX + 20,
            y: settingsFrame.midY - panelSize.height / 2
        )
        // If we'd overflow the right edge of the visible screen, fall back to the left.
        let visible = screen.visibleFrame
        if origin.x + panelSize.width > visible.maxX {
            origin.x = max(visible.minX, settingsFrame.minX - panelSize.width - 20)
        }
        // Keep within vertical bounds too.
        origin.y = min(max(origin.y, visible.minY), visible.maxY - panelSize.height)
        panel.setFrameOrigin(origin)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
