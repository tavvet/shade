# Changelog

All notable changes to Shade are documented in this file. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Rename a tab** — double-click a tab (or right-click → Rename) to pin a fixed
  name that overrides the automatic cwd / title, handy for long-lived tabs like
  `logs` or `ssh prod`. The name sticks through `cd` and even `[ssh]`; clear it
  with an empty name or right-click → Reset Name.
- **Font zoom** — `⌘+` / `⌘−` resize the terminal font live and `⌘0` resets it
  to the default (clamped to 8–32 pt and saved to settings). Matched by physical
  keyCode, so it works on any keyboard layout.

## [0.1.9] — 2026-06-15

### Added

- **Hide on focus loss** — opt in (Settings → Behavior, off by default) and the
  panel slides away whenever you switch to another app, the way Guake / Yakuake
  behave.
- **Blur material** — choose the frosted-glass style (HUD / under-window /
  sidebar / full-screen) in Settings → Appearance when background blur is on.
- **New tab in the current directory** — opt in (Settings → Behavior) and `⌘T`
  opens the new tab in the active tab's working directory instead of `$HOME`.
- **Cursor style** — pick block / bar / underline and toggle blink in Settings →
  Appearance (applied via DECSCUSR, so full-screen programs can still override it).
- **Visual bell** — opt in (Settings → Behavior) for a brief screen flash on the
  terminal bell.
- **Drag-and-drop** — drop a file from Finder onto the terminal and its
  shell-quoted path is inserted at the cursor.

## [0.1.8] — 2026-06-15

### Added

- **Background blur** behind the terminal (Appearance → Background blur, on by
  default). A frosted-glass backdrop shows through wherever the background
  opacity is below 100%, replacing the plain see-through-to-desktop look with
  the Guake / Yakuake frosted panel. Turn it off for raw transparency.
- **Tab status dots** — each tab shows a red dot when its last command exited
  non-zero (requires the OSC 133 shell snippet) and a neutral dot when a
  background tab has produced output you haven't looked at yet.
- **Command-finished notifications** — opt in (Settings → Notifications) and
  Shade posts a native notification when a command that ran past a threshold
  (default 30 s) finishes while the panel is hidden. Click it to bring the
  panel back. Needs the OSC 133 shell snippet.

## [0.1.7] — 2026-06-15

### Changed

- Detecting an `ssh` / `mosh` session no longer scans the whole system
  process table. Shade now walks the shell's own descendant tree, so the
  once-a-second context refresh costs a few syscalls per tab instead of one
  per process on the machine.
- Settings coalesce live-preview updates while you drag a slider or the
  link-color picker: the terminal re-applies font / opacity once the drag
  settles rather than on every frame.

### Fixed

- The background `git status` behind the badge could hang if git wrote
  enough to stderr to fill the pipe buffer (e.g. autocrlf warnings on a
  large dirty tree). Its stderr is now discarded so it can't block.

## [0.1.6] — 2026-05-21

### Fixed

- Git badge now stays fresh even when Shade's optional OSC 133 shell
  integration is not installed. The active session gets a weak fallback
  `git status` refresh while command-finished marks are absent; once OSC
  133 `D` marks are detected, those precise command-completion events take
  over again.
- Caps Lock no longer breaks Shade's custom shortcuts. Command/control/option
  matching now ignores the Caps Lock modifier, so `⌘T`, `⌘W`, `⌘K`, `⌃R`,
  and `⌥⌫` keep working while Caps Lock is enabled.
- Git branch detection now handles relative `.git` pointer files, as used by
  submodules and some worktrees (`gitdir: ../...` is resolved relative to the
  `.git` file's directory).
- Cancelled git refreshes now terminate any in-flight `git` subprocess before
  it can keep doing background work after rapid tab or cwd changes.
- Release builds are warning-clean again after silencing two unused-result
  warnings in the vendored SwiftTerm Metal renderer.

## [0.1.5] — 2026-05-19

### Fixed

- Scroll wheel now works inside full-screen TUI apps (vim, less, htop,
  k9s, Claude Code, micro, fzf, …). The vendored SwiftTerm previously
  always scrolled its own viewport in response to the wheel, which is
  a no-op while the alternate-screen buffer is active. `scrollWheel`
  now picks one of three paths:
  - If the app enabled mouse reporting (DECSET 1000 / 1002 / 1003 +
    1006), the wheel is forwarded as xterm button 4 / button 5 events
    so the app can react natively. Required for Claude CLI / micro /
    fzf — they consume plain `↑` / `↓` for their own navigation, so
    the arrow-key fallback alone made the wheel jump between messages
    / items instead of scrolling the view.
  - Otherwise, in the alternate-screen buffer, deltas are translated
    into `↑` / `↓` key presses. Covers vim / less / htop / k9s and
    matches iTerm2 / Alacritty / kitty defaults.
  - In the normal buffer, behavior is unchanged (scrolls scrollback).

## [0.1.4] — 2026-05-19

### Fixed

- About and Diagnostics now show the actual release version. The bundled
  `Info.plist` previously hardcoded `0.1.0` for `CFBundleShortVersionString`
  and never updated. The Makefile now stamps `git describe --tags --dirty`
  into the bundle at build time, so CI release builds get a clean `0.1.4`
  and local dev builds get a descriptive `0.1.3-2-gabc123-dirty`.

## [0.1.3] — 2026-05-19

### Added

- **Diagnostics window** — a read-only snapshot of what Shade currently
  sees: app version, macOS version, screen layout, hotkey, and active
  session state (shell, cwd, branch, git status, OSC 133 mark count).
  Includes a "Copy" button so the whole report can be pasted straight
  into a bug report. Available from both the status-bar menu and the
  App menu.

### Changed

- **Ctrl-D / `exit` now closes the tab instead of silently respawning
  the shell.** Matches standard macOS terminal behavior — on the last
  tab the existing "always keep at least one session" rule still
  spawns a fresh shell, so the panel never goes empty.

### Fixed

- **⌘T / ⌘W / ⌘K / ⌘⇧O on non-Latin keyboard layouts.** The shortcuts
  were dispatched through `event.charactersIgnoringModifiers`, which
  on Cyrillic / Greek / etc. input sources returns the layout-native
  character ("е" / "ц" / "л" / "щ") rather than falling back to QWERTY.
  Letter dispatch now goes through the physical keyCode the same way
  control-byte shortcuts do.
- **System ⌘T / ⌘⇧T no longer hijacks Shade's tab shortcuts.** macOS
  auto-installs "Show Tab Bar" / "Merge All Windows" key equivalents on
  any app with an NSWindow; Shade has its own tab model and now
  disables the system feature on launch.

## [0.1.2] — 2026-05-19

### Changed

- Git status badge no longer polls every second on the active tab. The
  per-tick `git status` fork is replaced by event-driven refresh via a
  new `GitRefreshCoordinator`: triggers are cwd change (OSC 7 / cwd
  poll), OSC 133 `D` (command finished), tab activation, and panel
  focus return. Debounced 350 ms with cancel-previous, plus a 5 s
  weak-reason cooldown so rapid tab/focus switching doesn't re-fork
  git. The cwd-polling timer still ticks for cwd / branch / remote
  indicator (in-process reads, cheap).

## [0.1.1] — 2026-05-19

### Added

- OSC 133 prompt-mark navigation: `⌘⇧↑` / `⌘⇧↓` jump between previous /
  next shell prompts, `⌘⇧O` copies the previous command's output to the
  clipboard. Opt-in by sourcing a shell snippet shipped in
  `integrations/shade.{zsh,bash,fish}` (also bundled inside
  `Shade.app/Contents/Resources/integrations/` for Homebrew users; see
  README "Prompt marking"). Marks are stored in scroll-invariant row
  coordinates so they survive scrollback rotation; stale entries are
  pruned lazily. Required three small additions to the vendored
  SwiftTerm: public `scrollInvariantCursorRow`, `scrollInvariantLinesTop`,
  and `maxScrollbackRow` accessors on `Terminal`.
- `Makefile` replaces the `Scripts/*.sh` shell scripts. Targets: `make`
  (build), `make run`, `make dmg`, `make icon`, `make clean`. Honors
  `CONFIG=debug|release` and `DEVELOPER_ID="…"` env vars.

## [0.1.0] — 2026-05-18

First public release.

### Added

- Status-bar app (no Dock icon) toggled by a global hotkey (default `F12`,
  rebindable in Settings).
- Borderless `NSPanel` that slides down from the top of the active screen
  with configurable duration; `Esc` hides it.
- Multi-tab terminal sessions backed by SwiftTerm:
  - `⌘T` / `⌘W` / `⌘1–9` / `⌃Tab` / `⌃⇧Tab`
  - Tab bar at the bottom showing index and abbreviated CWD
  - Shell prompt pinned to the bottom of the panel (Guake-style)
- Layout-agnostic Control+letter shortcuts (`⌃R`, `⌃A`, `⌃E`, `⌃W`, …) —
  work correctly on Cyrillic and other non-Latin keyboard layouts.
- Floating git badge in the top-right of the terminal: branch name plus
  `±N` / `+X` / `-Y` (files changed / insertions / deletions). Hidden
  outside git repositories. Branch read directly from `.git/HEAD`;
  status polled via `git` once a second for the active session only.
- Settings window: hotkey recorder, layout (width / height / horizontal
  alignment / target screen), appearance (font family + size, background
  opacity), animation duration, Open at Login, keyboard-shortcuts cheat
  sheet.
- Live-apply for font, opacity, and animation prefs (no toggle needed).
- About window with version, repository / license / acknowledgement links.
- Open at Login via `SMAppService`.
- Clickable links: `⌘`-hover highlights, `⌘`-click opens. URLs open via
  `NSWorkspace.shared.open`; file paths (absolute, `~`-prefixed, or relative
  to the shell's CWD) are revealed in Finder instead of launched in the
  default app, sidestepping the `paramErr (-50)` you get from
  `NSWorkspace.shared.open` on a bare file path.
- Link underline rendered in `systemYellow` instead of the cell's foreground
  color, so it stays readable when the terminal background is translucent.
  Required vendoring SwiftTerm to add a public `linkHoverColor` property —
  see `Vendor/SwiftTerm/` and `THIRDPARTY.md`.
- Color picker in Settings → Appearance for the link highlight (also tints
  the cells under the hovered link). Stored as `linkHighlightHex` in
  `defaults`. Settings briefly switches the app to `.regular` activation
  while open so `NSColorPanel` actually shows (LSUIElement / `.accessory`
  apps otherwise can't surface it).
- `⌘C` / `⌘V` / `⌘X` / `⌘A` now work inside the terminal. macOS only
  routes those key equivalents through `NSApp.mainMenu`, which Shade
  didn't have until now (LSUIElement apps skip the visible menu bar but
  still need the dispatch table). Installing a small Edit menu wires
  copy/paste/cut/select-all to SwiftTerm's existing responder-chain
  handlers.
- `⌥⌫` deletes the previous word (sends `ESC DEL`, matching
  Terminal.app and readline's `backward-kill-word`). Other Option+key
  combinations are left alone so SwiftTerm can still produce `´` / `©`
  / etc.
- `⌘X` best-effort cut: copies the selection to the pasteboard and
  sends N backspace bytes (`0x7F`) into the PTY so readline removes
  the same number of characters. Clean for `⇧←` / `⌥⇧←` style
  selections that end at the cursor; mid-line / multi-line cuts will
  delete from the cursor instead of from the highlighted region —
  there's no way to reposition readline from outside the shell.
- Keyboard selection in the visible buffer: `⇧←/→/↑/↓` (char-by-char),
  `⌥⇧←/→` (word-by-word), `⌘⇧←/→` (to line edges). Anchors at the
  cursor, extends from there, and SwiftTerm's normal "any keyDown
  clears selection" behavior tears it back down on the next keystroke
  (so a plain arrow returns control to shell navigation). `⌘C` copies
  whatever is selected. Required adding a public `extendKeyboardSelection`
  / `clearKeyboardSelection` API on the vendored SwiftTerm fork.
- Detect `ssh` / `mosh` / `tmate` in the shell's descendant pid tree
  (via `proc_listallpids` + `PROC_PIDTBSDINFO`). While a remote session
  is active, hide the git badge and replace the tab title with `[ssh]`
  — the local cwd polling and `git status` calls would otherwise show
  state from the local machine, which has nothing to do with what the
  user is looking at in the terminal.
- Shells start in `$HOME` instead of `/`.
- Unit tests (`swift test`) for `KeyCodes`, `Preferences`, `GitInfo`,
  `ProcessCwd`, and `TabsObservable.formatLabel`.

### Known limitations

- Bundle is ad-hoc signed; on first launch macOS Gatekeeper requires the
  user to clear the quarantine attribute or use the right-click → Open
  flow. Real Developer ID + notarization arrives in a follow-up release.
- No window splits, scrollback search, or session save/restore yet — so custom
  tab names don't survive a restart.
- macOS 13 minimum.

[Unreleased]: https://github.com/tavvet/shade/compare/v0.1.9...HEAD
[0.1.9]: https://github.com/tavvet/shade/releases/tag/v0.1.9
[0.1.8]: https://github.com/tavvet/shade/releases/tag/v0.1.8
[0.1.7]: https://github.com/tavvet/shade/releases/tag/v0.1.7
[0.1.6]: https://github.com/tavvet/shade/releases/tag/v0.1.6
[0.1.5]: https://github.com/tavvet/shade/releases/tag/v0.1.5
[0.1.4]: https://github.com/tavvet/shade/releases/tag/v0.1.4
[0.1.3]: https://github.com/tavvet/shade/releases/tag/v0.1.3
[0.1.2]: https://github.com/tavvet/shade/releases/tag/v0.1.2
[0.1.1]: https://github.com/tavvet/shade/releases/tag/v0.1.1
[0.1.0]: https://github.com/tavvet/shade/releases/tag/v0.1.0
