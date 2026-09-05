import AppKit
import Combine
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

        let inputBridge = SSHConnectionPickerInputBridge()
        let picker = SSHConnectionPickerPanel(
            contentViewController: NSHostingController(
                rootView: SSHConnectionPickerView(
                    controller: controller,
                    inputBridge: inputBridge,
                    onConnect: { [weak self] id in self?.connect(to: id) },
                    onDismiss: { [weak self] in self?.dismiss() },
                    onManage: { [weak self] in self?.manageConnections() }
                )
            )
        )
        picker.onCancel = { [weak self] in self?.dismiss() }
        picker.onBecomeKey = { inputBridge.requestFocus() }
        picker.onMoveSelection = { inputBridge.moveSelection($0) }
        picker.onQuickSlot = { [weak self] number in self?.connectQuickSlot(number) }
        let visibleFrame = parent.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? parent.frame
        picker.setFrame(
            SSHConnectionPickerLayout.frame(
                parentFrame: parent.frame,
                visibleFrame: visibleFrame
            ),
            display: false
        )

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

        if parent?.isVisible == true {
            parent?.makeKeyAndOrderFront(nil)
        }
    }

    private func connect(to id: UUID) {
        guard controller.connect(to: id) else { return }
        dismiss()
    }

    private func connectQuickSlot(_ number: Int) {
        guard controller.connectQuickSlot(number) else { return }
        dismiss()
    }

    private func manageConnections() {
        dismiss()
        openConnectionSettings()
    }
}

/// A borderless key window aligned with the parent dropdown panel. It expands
/// to a usable minimum size when the user's terminal panel is very small.
@MainActor
final class SSHConnectionPickerPanel: NSPanel {
    var onCancel: (() -> Void)?
    var onBecomeKey: (() -> Void)?
    var onMoveSelection: ((SSHConnectionPickerSelectionDirection) -> Void)?
    var onQuickSlot: ((Int) -> Void)?

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

    override func becomeKey() {
        super.becomeKey()
        onBecomeKey?()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let shortcut = PanelShortcutResolver.resolve(
            keyCode: event.keyCode,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
            modifierFlags: event.modifierFlags,
            tabCount: 0
        ), case .connectQuickSlot(let number) = shortcut,
           let onQuickSlot {
            onQuickSlot(number)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           let direction = SSHConnectionPickerKeyNavigation.direction(
               keyCode: event.keyCode,
               modifierFlags: event.modifierFlags,
               hasMarkedText: activeTextInputHasMarkedText
           ), let onMoveSelection {
            onMoveSelection(direction)
            return
        }
        super.sendEvent(event)
    }

    private var activeTextInputHasMarkedText: Bool {
        (firstResponder as? any NSTextInputClient)?.hasMarkedText() == true
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

@MainActor
final class SSHConnectionPickerInputBridge: ObservableObject {
    @Published private(set) var focusGeneration = 0
    let selectionMoves = PassthroughSubject<SSHConnectionPickerSelectionDirection, Never>()

    func requestFocus() {
        focusGeneration &+= 1
    }

    func moveSelection(_ direction: SSHConnectionPickerSelectionDirection) {
        selectionMoves.send(direction)
    }
}

enum SSHConnectionPickerLayout {
    static let minimumWidth: CGFloat = 520
    // Covers the tallest state: header + search + two-line load error +
    // empty-library guidance + footer + the card's outer breathing room.
    static let minimumHeight: CGFloat = 520

    static func frame(parentFrame: NSRect, visibleFrame: NSRect) -> NSRect {
        let width = min(max(parentFrame.width, minimumWidth), visibleFrame.width)
        let height = min(max(parentFrame.height, minimumHeight), visibleFrame.height)

        let centeredX = parentFrame.midX - width / 2
        let x = min(max(centeredX, visibleFrame.minX), visibleFrame.maxX - width)
        let alignedY = parentFrame.maxY - height
        let y = min(max(alignedY, visibleFrame.minY), visibleFrame.maxY - height)

        return NSRect(x: x, y: y, width: width, height: height)
    }
}
