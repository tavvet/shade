import AppKit
import SwiftTerm

/// Sits between `LocalProcessTerminalView` and SwiftTerm so we can intercept
/// `requestOpenLink`. SwiftTerm dispatches link activations through its
/// `terminalDelegate`; `LocalProcessTerminalView` installs itself there and
/// relies on the protocol-extension default that just does
/// `NSWorkspace.shared.open(URL(string:link))` — which paramErr's (-50) on
/// bare file paths. Subclassing didn't work (Swift's witness-table dispatch
/// picks the default extension over a subclass method that doesn't carry
/// `override`), so we install this proxy and forward every other method
/// untouched to the original delegate.
///
/// `TerminalViewDelegate` is not `@MainActor`-isolated upstream, so this
/// proxy can't be either (the conformance would no longer match the protocol
/// contract). In practice SwiftTerm dispatches all of these callbacks on the
/// main thread, which is why `onOpenLink` is allowed to call back into
/// `TerminalSession` via `MainActor.assumeIsolated`.
final class TerminalDelegateProxy: NSObject, TerminalViewDelegate {
    weak var forward: TerminalViewDelegate?
    var onOpenLink: ((String) -> Void)?

    init(forward: TerminalViewDelegate?) {
        self.forward = forward
    }

    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        onOpenLink?(link)
    }

    // MARK: - Pure forwarding for everything else.

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
        forward?.bell(source: source)
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

/// Thin wrapper around SwiftTerm's LocalProcessTerminalView that owns one shell session.
@MainActor
final class TerminalSession: NSObject {
    static let titleDidChange = Notification.Name("ShadeTerminalSessionTitleDidChange")

    /// Invoked when the underlying shell process exits — whether via Ctrl-D
    /// on an empty prompt, an explicit `exit`, or a crash. The controller
    /// installs this on each new session to close the corresponding tab
    /// (its "always keep at least one tab" rule handles the last-tab case).
    /// Closure callback rather than a notification because `Notification`
    /// isn't Sendable across the parser → main hop under strict concurrency.
    var onExit: (@MainActor () -> Void)?

    let view: LocalProcessTerminalView
    private let delegateProxy: TerminalDelegateProxy
    private var didPadInitialPrompt = false
    private var sawOsc133CommandDone = false
    private(set) var promptMarks: [PromptMark] = []

    private(set) var title: String = "" {
        didSet { notifyTitleChanged() }
    }

    private(set) var cwd: String = "" {
        didSet {
            // Drive git-status refreshes off cwd changes (instead of polling).
            // Any path where this differs from the previous cwd schedules a
            // strong-reason refresh; emptying cwd (e.g. when ssh starts and
            // local state is masked) cancels any pending refresh and clears
            // the status badge directly.
            if cwd != oldValue {
                if cwd.isEmpty {
                    gitRefresh.cancel()
                    if gitStatus != nil { gitStatus = nil }
                } else {
                    gitRefresh.schedule(path: cwd, reason: .cwdChanged)
                }
            }
            // CWD changes also affect displayTitle when no explicit title was set.
            guard title.isEmpty else { return }
            notifyTitleChanged()
        }
    }

    private lazy var gitRefresh: GitRefreshCoordinator = GitRefreshCoordinator(
        apply: { [weak self] status in self?.gitStatus = status }
    )

    private(set) var branch: String = "" {
        didSet { notifyTitleChanged() }
    }

    private(set) var gitStatus: GitStatus? = nil {
        didSet {
            guard oldValue != gitStatus else { return }
            notifyTitleChanged()
        }
    }

    /// Non-nil when the shell has launched ssh/mosh/etc — the local cwd/git
    /// heuristics no longer reflect what the user sees, so callers should mask
    /// branch/status and the displayTitle switches to "[name]" (e.g. "[ssh]").
    private(set) var remoteIndicator: String? = nil {
        didSet {
            guard oldValue != remoteIndicator else { return }
            notifyTitleChanged()
        }
    }

    let shellName: String

    /// What the tab bar shows: shell-provided title or abbreviated CWD or shell name.
    /// The git branch is rendered separately as a floating badge over the terminal.
    /// When we're inside an ssh/mosh session, local cwd/branch info is meaningless,
    /// so we surface a "[ssh]"-style indicator instead.
    var displayTitle: String {
        if let remote = remoteIndicator { return "[\(remote)]" }
        if !title.isEmpty { return title }
        if !cwd.isEmpty   { return abbreviateHome(cwd) }
        return shellName
    }

    private func notifyTitleChanged() {
        NotificationCenter.default.post(name: Self.titleDidChange, object: self)
    }

    private func abbreviateHome(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    override init() {
        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        shellName = (shellPath as NSString).lastPathComponent
        view = LocalProcessTerminalView(frame: .zero)
        // Capture the delegate LocalProcessTerminalView installed in its init,
        // then slot our proxy in front of it.
        delegateProxy = TerminalDelegateProxy(forward: view.terminalDelegate)
        super.init()
        view.processDelegate = self
        view.terminalDelegate = delegateProxy
        delegateProxy.onOpenLink = { [weak self] link in
            MainActor.assumeIsolated { self?.openLink(link) }
        }
        // OSC 133 prompt marks. Snapshot the cursor row synchronously inside
        // the parser callback (which doesn't run on main); hop to the main
        // actor to mutate session state. Capturing the terminal weakly avoids
        // a retain cycle through parser.oscHandlers.
        let terminal = view.getTerminal()
        terminal.registerOscHandler(code: 133) { [weak self, weak terminal] data in
            guard let terminal else { return }
            let row = terminal.scrollInvariantCursorRow
            let bytes = Array(data)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.recordPromptMark(payload: bytes, row: row)
                }
            }
        }
        view.translatesAutoresizingMaskIntoConstraints = false
        view.nativeForegroundColor = NSColor(white: 0.92, alpha: 1.0)
        apply(Preferences.load())
    }

    func start() {
        guard !view.process.running else { return }
        // Only pad once, on the very first start. On auto-restart (after the user
        // types `exit`) the previous session's output already fills the visible
        // area, so feeding more newlines would push the new prompt off-screen.
        if !didPadInitialPrompt {
            padCursorToBottom()
            didPadInitialPrompt = true
        }
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        view.startProcess(
            executable: shell,
            args: ["-l"],
            environment: nil,
            execName: "-" + shellName  // leading dash → login shell
        )
    }

    /// Push the emulator cursor to the last visible row so the shell prompt
    /// appears at the bottom of the panel (Guake-style), not the top.
    private func padCursorToBottom() {
        let rows = view.getTerminal().rows
        guard rows > 1 else { return }
        view.feed(text: String(repeating: "\n", count: rows - 1))
    }

    func apply(_ prefs: Preferences) {
        view.font = prefs.terminalFont()
        view.nativeBackgroundColor = NSColor(white: 0.08, alpha: prefs.backgroundOpacity)
        view.linkHoverColor = prefs.linkHighlightColor()
        view.wantsLayer = true
        view.layer?.isOpaque = false
        view.layer?.backgroundColor = NSColor.clear.cgColor
    }

    func terminate() {
        if view.process.running {
            kill(view.process.shellPid, SIGTERM)
        }
    }

    private func recordPromptMark(payload: [UInt8], row: Int) {
        guard let mark = PromptMark.parse(payload: payload[...], row: row) else { return }
        pruneStalePromptMarks()
        promptMarks.append(mark)
        // `D` (command finished) is the canonical "shell did something — git
        // status may have changed" signal. Drive a strong-reason refresh.
        if case .commandDone = mark.kind {
            sawOsc133CommandDone = true
            if !cwd.isEmpty {
                gitRefresh.schedule(path: cwd, reason: .commandFinished)
            }
        }
    }

    private func pruneStalePromptMarks() {
        let terminal = view.getTerminal()
        // Drop marks whose row has fallen out of scrollback. Lazy — runs on
        // record and on jump, which is enough to keep the list bounded by
        // recent activity without a separate timer.
        promptMarks.removeAll { terminal.getScrollInvariantLine(row: $0.row) == nil }
    }

    /// Scroll the viewport up to the previous OSC 133 `A` (prompt-start) mark
    /// strictly above the current viewport top. Returns `false` if there is
    /// no earlier mark (already at the oldest prompt, or no marks at all).
    @discardableResult
    func jumpToPreviousPrompt() -> Bool {
        jump(direction: .previous)
    }

    /// Mirror of `jumpToPreviousPrompt()`, scrolling down to the next mark.
    @discardableResult
    func jumpToNextPrompt() -> Bool {
        jump(direction: .next)
    }

    private enum JumpDirection { case previous, next }

    /// Copy the most recently completed command's output to the system
    /// clipboard. Requires the shell to emit OSC 133 `C`/`D` around its
    /// commands (see the README "Shell integration" section). Returns
    /// `false` if no completed C/D pair exists or the command produced
    /// no output.
    @discardableResult
    func copyLastCommandOutput() -> Bool {
        pruneStalePromptMarks()
        guard let range = PromptMark.lastCommandOutputRange(in: promptMarks) else { return false }
        let terminal = view.getTerminal()
        var lines: [String] = []
        for row in range {
            guard let bufferLine = terminal.getScrollInvariantLine(row: row) else { continue }
            lines.append(bufferLine.translateToString(trimRight: true))
        }
        let text = lines.joined(separator: "\n")
        guard !text.isEmpty else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return true
    }

    private func jump(direction: JumpDirection) -> Bool {
        pruneStalePromptMarks()
        let terminal = view.getTerminal()
        let viewportTopInvariant = terminal.scrollInvariantLinesTop + terminal.buffer.yDisp
        let mark: PromptMark?
        switch direction {
        case .previous:
            mark = PromptMark.previousPromptStart(before: viewportTopInvariant, in: promptMarks)
        case .next:
            mark = PromptMark.nextPromptStart(after: viewportTopInvariant, in: promptMarks)
        }
        guard let mark else { return false }
        // Clamp into the valid yDisp range. Without this, a mark near the
        // bottom of scrollback (cursor area) would scroll the viewport past
        // the last line — empty rows appear below the content and the
        // translucent panel background shows through, which reads as "the
        // panel went transparent."
        let rawViewportRow = mark.row - terminal.scrollInvariantLinesTop
        let viewportRow = max(0, min(rawViewportRow, terminal.maxScrollbackRow))
        view.scrollTo(row: viewportRow)
        return true
    }

    /// Re-read the shell's working directory and current git branch — both
    /// fast (libproc lookup + `.git/HEAD` read). `git status` is no longer
    /// part of this tick; it runs through `GitRefreshCoordinator`, driven by
    /// cwd changes and OSC 133 command-finished marks instead of polling.
    func refreshContext() {
        guard view.process.running else { return }
        let shellPid = view.process.shellPid

        // Remote detection comes first — if we're in ssh/mosh the local cwd / git
        // numbers don't describe the user's session and we should skip them.
        let newRemote = ProcessTree.remoteIndicator(forShell: shellPid)
        if newRemote != remoteIndicator {
            remoteIndicator = newRemote
        }

        if newRemote != nil {
            // Mask local info so the UI doesn't lie about what the user is seeing.
            // Also clear `title` — the remote shell typically pushes its own OSC 0
            // (e.g. "root@localhost"), and after `exit` the local shell won't reset
            // it, so without this you'd see a stale remote title on the tab.
            if !cwd.isEmpty { cwd = "" }      // cwd.didSet cancels gitRefresh + clears gitStatus
            if !branch.isEmpty { branch = "" }
            if !title.isEmpty { title = "" }
            return
        }

        if let path = ProcessCwd.read(pid: shellPid), path != cwd {
            cwd = path
        }
        let newBranch = cwd.isEmpty ? "" : (GitInfo.branch(forCwd: cwd) ?? "")
        if newBranch != branch {
            branch = newBranch
        }
    }

    /// Called when this session's tab becomes active. Pulls fresh
    /// cwd/branch immediately and schedules a status refresh under a weak
    /// reason — the coordinator's rate limit will skip it if we just
    /// refreshed (e.g. tab switched twice within a few seconds).
    func tabActivated() {
        refreshContext()
        if !cwd.isEmpty {
            gitRefresh.schedule(path: cwd, reason: .tabActivated)
        }
    }

    /// Called when the panel regains key-window status. Same weak-reason
    /// schedule as `tabActivated()` — covers the case where the user made
    /// changes in another tool while the panel was hidden.
    func focusReturned() {
        if !cwd.isEmpty {
            gitRefresh.schedule(path: cwd, reason: .focusReturned)
        }
    }

    /// Keeps the git badge fresh for users who have not installed Shade's OSC 133
    /// shell snippet. Once we see command-finished marks, those become the precise
    /// trigger and this fallback stays quiet.
    func fallbackRefreshGitStatusIfNeeded() {
        guard view.process.running else { return }
        guard !sawOsc133CommandDone, !cwd.isEmpty, !branch.isEmpty else { return }
        gitRefresh.schedule(path: cwd, reason: .fallbackPoll)
    }
}

extension TerminalSession: LocalProcessTerminalViewDelegate {
    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.title = title
            }
        }
    }
    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        let path = directory ?? ""
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.cwd = path
            }
        }
    }

    private func openLink(_ rawLink: String) {
        let link = rawLink.trimmingCharacters(in: .whitespaces)
        // 1. Explicit file:// URL — reveal in Finder rather than launching the default app.
        if let url = URL(string: link), url.isFileURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }
        // 2. Absolute or ~-relative file path — reveal in Finder if it exists.
        if link.hasPrefix("/") || link.hasPrefix("~") {
            let expanded = (link as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expanded) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: expanded)])
                return
            }
        }
        // 3. Relative path against the shell's current working directory.
        if !link.isEmpty, !cwd.isEmpty,
           !link.contains("://"),
           !link.hasPrefix("/") {
            let candidate = (cwd as NSString).appendingPathComponent(link)
            if FileManager.default.fileExists(atPath: candidate) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: candidate)])
                return
            }
        }
        // 4. Anything else with a real URL scheme — open via the default handler.
        // Don't fall back to NSWorkspace.open for schemeless garbage: SwiftTerm
        // shouldn't produce it, but `URL(string:)` happily succeeds on plain
        // words and NSWorkspace would then surface a "could not open" alert.
        if let url = URL(string: link), url.scheme != nil {
            NSWorkspace.shared.open(url)
        }
    }

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                // Tell the controller to close this tab. Standard macOS
                // terminal behavior — Ctrl-D / `exit` ends the tab rather
                // than silently respawning the shell inside it. Last-tab
                // case is handled by TerminalsController.close, which
                // spawns a fresh session when none are left.
                self?.onExit?()
            }
        }
    }
}
