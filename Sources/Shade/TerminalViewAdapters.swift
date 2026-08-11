import AppKit
import SwiftTerm

/// Sits between `LocalProcessTerminalView` and SwiftTerm so Shade can intercept
/// link activation and bell events while forwarding the rest unchanged.
/// SwiftTerm's protocol-extension default opens every link as a URL, which
/// fails for bare file paths. A subclass method cannot replace that default
/// because witness-table dispatch still selects the original conformance, so
/// the delegate must be wrapped instead.
///
/// `TerminalViewDelegate` is not `@MainActor`-isolated upstream. SwiftTerm
/// dispatches these callbacks on the main thread in practice; callers that
/// enter actor-isolated state must make that assumption explicitly.
final class TerminalDelegateProxy: NSObject, TerminalViewDelegate {
    weak var forward: TerminalViewDelegate?
    var onOpenLink: ((String) -> Void)?
    /// Return true when Shade handled the bell and the default audible bell
    /// should be suppressed.
    var onBell: (() -> Bool)?

    init(forward: TerminalViewDelegate?) {
        self.forward = forward
    }

    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        onOpenLink?(link)
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        forward?.sizeChanged(source: source, newCols: newCols, newRows: newRows)
    }

    func setTerminalTitle(source: TerminalView, title: String) {
        forward?.setTerminalTitle(source: source, title: title)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        forward?.hostCurrentDirectoryUpdate(source: source, directory: directory)
    }

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        forward?.send(source: source, data: data)
    }

    func scrolled(source: TerminalView, position: Double) {
        forward?.scrolled(source: source, position: position)
    }

    func bell(source: TerminalView) {
        if onBell?() != true {
            forward?.bell(source: source)
        }
    }

    func clipboardCopy(source: TerminalView, content: Data) {
        forward?.clipboardCopy(source: source, content: content)
    }

    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {
        forward?.iTermContent(source: source, content: content)
    }

    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {
        forward?.rangeChanged(source: source, startY: startY, endY: endY)
    }
}

/// Taps PTY output for background-tab activity and accepts file drops without
/// adding either concern to the shell-session coordinator. `dataReceived`
/// runs for hidden sessions too, unlike display-driven delegate callbacks.
final class ActivityTerminalView: LocalProcessTerminalView {
    var onData: (() -> Void)?
    var onUserInput: (() -> Void)?

    override func dataReceived(slice: ArraySlice<UInt8>) {
        onData?()
        super.dataReceived(slice: slice)
    }

    override func paste(_ sender: Any) {
        onUserInput?()
        super.paste(sender)
    }

    func sendUserInput(_ bytes: [UInt8]) {
        onUserInput?()
        send(bytes)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        registerForDraggedTypes([.fileURL])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: nil) ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              !urls.isEmpty else { return false }
        let text = urls.map { Self.shellQuoted($0.path) }.joined(separator: " ") + " "
        sendUserInput(Array(text.utf8))
        return true
    }

    /// POSIX single-quote a path so spaces and shell metacharacters survive intact.
    nonisolated static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
