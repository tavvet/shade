import AppKit

/// Owns the AppKit container that displays the active terminal view.
/// Session selection decides what to show; this type handles only view
/// replacement, edge constraints, layout and keyboard focus.
@MainActor
final class TerminalViewHost {
    let containerView: NSView

    init(containerView: NSView = NSView()) {
        self.containerView = containerView
        containerView.translatesAutoresizingMaskIntoConstraints = false
    }

    func show(_ view: NSView) {
        containerView.subviews.forEach { $0.removeFromSuperview() }
        view.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: containerView.topAnchor),
            view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
        ])

        // SwiftTerm must know its real rows before the shell starts; otherwise
        // the first prompt is laid out against its default 24-row buffer.
        containerView.layoutSubtreeIfNeeded()
    }

    func focus(_ view: NSView) {
        containerView.window?.makeFirstResponder(view)
    }
}
