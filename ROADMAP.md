# Roadmap

A non-binding backlog of features under consideration for Shade, ordered roughly
by leverage-to-effort rather than commitment. Effort tags are gut estimates:
**S** ≈ an afternoon, **M** ≈ a focused day or two, **L** ≈ multi-day with design.

Guiding bias: keyboard-first, native to macOS, stays minimal. A feature earns its
place by being either a Guake / Yakuake / iTerm2 staple users miss, or something
only a native Mac app can do well.

## Parity — Guake / Yakuake / iTerm2 staples

- **Scrollback search (`⌘F`)** — *M.*
  Find-in-buffer with next / previous and highlight. Listed under CHANGELOG
  "Known limitations".
  *Why:* core terminal feature and a natural fit for the keyboard-first ethos.
  *How:* scan buffer text via the fork's scroll-invariant accessors; scroll to a
  match and select it with the existing `extendKeyboardSelection`. Multi-match
  highlighting may need a small fork addition. New SwiftUI search overlay.

- **Tab reorder / color labels** — *M.*
  Drag-to-reorder tabs and an optional color tag. (Tab **rename** shipped — a
  user-set name now overrides the cwd auto-title via `userTitle`.)
  *How:* reorder the `sessions` array from `TabBar` drags; a per-session tint.
  No fork API.

- **Broadcast input to all tabs** — *M.*
  iTerm2-style: type once, send to every session.
  *How:* a mode flag that fans `panelSendToActiveTerminal` out to all sessions,
  with a visible indicator so it can't be left on by accident.

## Bigger bets

- **Color themes / ANSI palette** — *L.*
  Replace the hardcoded foreground / background (`0.92` / `0.08`) with named
  schemes — 16 ANSI colors plus fg / bg / cursor — and import of `.itermcolors`
  or base16.
  *Why:* the single biggest appearance upgrade available.
  *How:* a Theme model in Preferences, applied through SwiftTerm's color table in
  `TerminalSession.apply`; a theme picker in Settings.

- **Session save / restore** — *M.*
  Remember open tabs (cwd + title) and rebuild them on the next launch.
  *Why:* CHANGELOG "Known limitations".
  *How:* persist tab descriptors on change / quit and recreate them on launch.
  Shares the spawn-in-a-given-cwd mechanism with "new tab inherits cwd".

## Native-macOS delighters

- **Open a tab in the frontmost app's directory** — *M.*
  Press the hotkey with Finder (or a supported IDE) frontmost → the new tab is
  already `cd`'d there. Impossible on the Linux originals.
  *How:* read the frontmost window's path (Accessibility / Apple Events) at toggle
  time. Needs an extra permission, so gate it behind a toggle.

## Explicitly deferred

- **Window splits / panes** — set aside for now. Would need a pane-tree model and
  focus routing on top of today's single-active-view `TerminalsController`: a large
  change, and not the current priority.

- **Warp-style as-you-type completion dropdown** — not planned. Rendering our own
  completion overlay means owning the input line and discarding the user's `zle`,
  vi-mode and key bindings — a different product, and the opposite of "your shell
  stays your shell." The opt-in shell enrichment (richer `compinit` completion via
  a bundled `ZDOTDIR`, see CHANGELOG) is the native, lightweight alternative we
  ship instead.
