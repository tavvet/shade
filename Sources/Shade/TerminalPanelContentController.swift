import AppKit
import SwiftUI

/// Builds and updates the visual hierarchy hosted by the dropdown panel.
@MainActor
final class TerminalPanelContentController {
    private let terminals: TerminalsController
    private let tabs: TabsObservable
    private let inputSource: InputSourceMonitor
    private weak var blurView: NSVisualEffectView?

    init(
        terminals: TerminalsController,
        tabs: TabsObservable,
        inputSource: InputSourceMonitor
    ) {
        self.terminals = terminals
        self.tabs = tabs
        self.inputSource = inputSource
    }

    func install(in panel: DropdownPanel) {
        let tabBar = TabBarView(
            tabs: tabs,
            inputSource: inputSource,
            onSelect: { [weak self] in self?.terminals.select(at: $0) },
            onClose: { [weak self] in self?.terminals.close(at: $0) },
            onNew: { [weak self] in self?.terminals.newSession() },
            onRename: { [weak self] index, name in self?.terminals.renameSession(at: index, to: name) },
            onEditEnd: { [weak self] in self?.focusActiveTerminal() }
        )
        let tabBarHost = NSHostingView(rootView: tabBar)
        tabBarHost.translatesAutoresizingMaskIntoConstraints = false

        let badgeHost = NSHostingView(rootView: BranchBadgeView(tabs: tabs))
        badgeHost.translatesAutoresizingMaskIntoConstraints = false

        let terminalOverlay = NSView()
        terminalOverlay.translatesAutoresizingMaskIntoConstraints = false
        terminalOverlay.addSubview(terminals.containerView)
        terminalOverlay.addSubview(badgeHost)
        NSLayoutConstraint.activate([
            terminals.containerView.topAnchor.constraint(equalTo: terminalOverlay.topAnchor),
            terminals.containerView.bottomAnchor.constraint(equalTo: terminalOverlay.bottomAnchor),
            terminals.containerView.leadingAnchor.constraint(equalTo: terminalOverlay.leadingAnchor),
            terminals.containerView.trailingAnchor.constraint(equalTo: terminalOverlay.trailingAnchor),
            badgeHost.topAnchor.constraint(equalTo: terminalOverlay.topAnchor),
            badgeHost.trailingAnchor.constraint(equalTo: terminalOverlay.trailingAnchor),
        ])

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 0
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(terminalOverlay)
        stack.addArrangedSubview(tabBarHost)
        NSLayoutConstraint.activate([
            tabBarHost.heightAnchor.constraint(equalToConstant: 28),
            tabBarHost.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            tabBarHost.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            terminalOverlay.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            terminalOverlay.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
        ])

        let prefs = PreferencesStore.standard.load()
        let blur = NSVisualEffectView()
        blur.material = prefs.blurMaterial.nsMaterial
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.appearance = NSAppearance(named: .darkAqua)
        blur.translatesAutoresizingMaskIntoConstraints = false
        blur.isHidden = !prefs.backgroundBlur
        blurView = blur
        inputSource.setEnabled(prefs.showInputSourceIndicator)

        let root = NSView()
        root.addSubview(blur)
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            blur.topAnchor.constraint(equalTo: root.topAnchor),
            blur.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            blur.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        ])

        panel.contentView = root
    }

    func apply(_ prefs: Preferences) {
        blurView?.isHidden = !prefs.backgroundBlur
        blurView?.material = prefs.blurMaterial.nsMaterial
        inputSource.setEnabled(prefs.showInputSourceIndicator)
    }

    /// Returns keyboard focus after an inline tab rename or app activation.
    func focusActiveTerminal() {
        terminals.focusActiveSession()
    }
}
