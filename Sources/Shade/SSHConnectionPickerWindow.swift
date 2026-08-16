import AppKit
import SwiftUI

/// Presents the connection picker as a separate child window above Shade.
/// Nothing is installed in the terminal panel's view hierarchy until the user
/// explicitly invokes the picker.
@MainActor
final class SSHConnectionPickerPresenter {
    private let controller: SSHConnectionsController
    private let openConnectionSettings: @MainActor () -> Void

    private weak var parentPanel: DropdownPanel?
    private var pickerPanel: SSHConnectionPickerPanel?

    init(
        controller: SSHConnectionsController,
        openConnectionSettings: @escaping @MainActor () -> Void
    ) {
        self.controller = controller
        self.openConnectionSettings = openConnectionSettings
    }

    func present(over parent: DropdownPanel) {
        if let pickerPanel {
            pickerPanel.makeKeyAndOrderFront(nil)
            return
        }

        controller.reload()
        controller.presentPicker()

        let picker = SSHConnectionPickerPanel(
            contentViewController: NSHostingController(
                rootView: SSHConnectionPickerView(
                    controller: controller,
                    onConnect: { [weak self] id in self?.connect(to: id) },
                    onDismiss: { [weak self] in self?.dismiss() },
                    onManage: { [weak self] in self?.manageConnections() }
                )
            )
        )
        picker.onCancel = { [weak self] in self?.dismiss() }
        picker.setFrame(parent.frame, display: false)

        parentPanel = parent
        pickerPanel = picker
        parent.addChildWindow(picker, ordered: .above)
        picker.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        let parent = parentPanel
        if let pickerPanel {
            parent?.removeChildWindow(pickerPanel)
            pickerPanel.orderOut(nil)
            pickerPanel.contentViewController = nil
        }

        pickerPanel = nil
        parentPanel = nil
        controller.dismissPicker()

        if parent?.isVisible == true {
            parent?.makeKeyAndOrderFront(nil)
        }
    }

    private func connect(to id: UUID) {
        guard controller.connect(to: id) else { return }
        dismiss()
    }

    private func manageConnections() {
        dismiss()
        openConnectionSettings()
    }
}

/// A borderless key window that covers only its parent dropdown panel.
@MainActor
private final class SSHConnectionPickerPanel: NSPanel {
    var onCancel: (() -> Void)?

    init(contentViewController: NSViewController) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.contentViewController = contentViewController
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
