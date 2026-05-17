# Changelog

All notable changes to Shade are documented in this file. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] — 2026-05-17

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
- Shells start in `$HOME` instead of `/`.
- Unit tests (`swift test`) for `KeyCodes`, `Preferences`, `GitInfo`,
  `ProcessCwd`, and `TabsObservable.formatLabel`.

### Known limitations

- Bundle is ad-hoc signed; on first launch macOS Gatekeeper requires the
  user to clear the quarantine attribute or use the right-click → Open
  flow. Real Developer ID + notarization arrives in a follow-up release.
- No window splits, scrollback search, or session save/restore yet.
- macOS 13 minimum.

[Unreleased]: https://github.com/tavvet/shade/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/tavvet/shade/releases/tag/v0.1.0
