# Roadmap

A non-binding backlog of features under consideration for Shade, ordered roughly
by leverage-to-effort rather than commitment. Effort tags are gut estimates:
**S** ≈ an afternoon, **M** ≈ a focused day or two, **L** ≈ multi-day with design.

Guiding bias: keyboard-first, native to macOS, stays minimal. A feature earns its
place by being either a Guake / Yakuake / iTerm2 staple users miss, or something
only a native Mac app can do well.

## Near-term — high leverage (reuses infrastructure already in the tree)

- **"Command finished" notification while the panel is hidden** — *M.*
  When a long command completes while Shade is down, post a native notification
  with its exit status.
  *Why:* also rides the OSC 133 marks (`C` start → `D` done gives duration), and
  the panel already knows when it's hidden.
  *How:* time the `C`→`D` gap; if `!panel.isVisible` and duration exceeds a
  threshold, fire a `UNUserNotification`. New small notifier + a Settings
  toggle/threshold.

- **Blur material choice** — *S.*
  Let the user pick the `NSVisualEffectView` material for the background blur
  (e.g. HUD vs. under-window) instead of the fixed dark HUD it ships with.

- **New tab inherits the active tab's cwd** — *S.*
  Optional: `⌘T` opens in the current directory instead of `$HOME`.
  *Why:* one of the most common drop-down-terminal requests.
  *How:* read `activeSession.cwd` and spawn the shell there. Caveat: SwiftTerm's
  `startProcess` inherits the process cwd — needs a `chdir`-around-spawn or a
  vendored cwd parameter. Settings toggle.

- **Hide on focus loss** — *S.*
  Optional: the panel auto-hides when it stops being the key window (a Yakuake
  default).
  *Why:* staple of the genre.
  *How:* symmetric to the existing `onBecomeKey` / `hide()` — hide on `resignKey`
  when the pref is on. Must not fire while Settings or the color panel is open
  (those already flip activation policy). Settings toggle.

- **Cursor style & visual bell** — *S.*
  Block / bar / underline + blink; a screen flash instead of (or alongside) the
  audible bell.
  *How:* cursor options via SwiftTerm; the `bell(source:)` delegate is already
  forwarded through `TerminalDelegateProxy`. Lives in Appearance settings.

## Parity — Guake / Yakuake / iTerm2 staples

- **Scrollback search (`⌘F`)** — *M.*
  Find-in-buffer with next / previous and highlight. Listed under CHANGELOG
  "Known limitations".
  *Why:* core terminal feature and a natural fit for the keyboard-first ethos.
  *How:* scan buffer text via the vendored scroll-invariant accessors; scroll to a
  match and select it with the existing `extendKeyboardSelection`. Multi-match
  highlighting may need a small vendored addition. New SwiftUI search overlay.

- **Tab rename / reorder / color labels** — *M.*
  A user-set tab title (overriding the cwd auto-title), drag-to-reorder, and an
  optional color tag.
  *How:* a user-title field with precedence in `displayTitle`; reorder the
  `sessions` array from `TabBar` drags; a per-session tint. No vendored API.

- **Broadcast input to all tabs** — *M.*
  iTerm2-style: type once, send to every session.
  *How:* a mode flag that fans `panelSendToActiveTerminal` out to all sessions,
  with a visible indicator so it can't be left on by accident.

- **Drag-and-drop a file into the terminal** — *S.*
  Drop a Finder item → its (quoted) path is inserted at the cursor.
  *How:* register a dragging destination on the terminal view and send the path
  bytes on drop.

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
