# Changelog

All notable changes to Shade are documented in this file. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
- No window splits, scrollback search, or session save/restore yet.
- macOS 13 minimum.

[Unreleased]: https://github.com/tavvet/shade/compare/v0.1.2...HEAD
[0.1.2]: https://github.com/tavvet/shade/releases/tag/v0.1.2
[0.1.1]: https://github.com/tavvet/shade/releases/tag/v0.1.1
[0.1.0]: https://github.com/tavvet/shade/releases/tag/v0.1.0
