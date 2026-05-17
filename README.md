# Shade

A drop-down terminal for macOS in the spirit of [Guake] / [Yakuake] on Linux —
hidden by default, slides down from the top of the screen on a global hotkey,
disappears just as fast. Tabs, transparency, keyboard-first.

Native Swift / SwiftUI. Status-bar app (no Dock icon). MIT licensed.

[Guake]: http://guake-project.org/
[Yakuake]: https://apps.kde.org/yakuake/

---

## Features

- **Global hotkey** to toggle the panel (default `F12`, rebind in Settings).
- **Slides** down from the top of the active screen, fades back up.
- **Tabs** with `⌘T` / `⌘W` / `⌘1…9` / `⌃Tab` (macOS-standard).
- **Tab titles** track the shell's current working directory (no `.zshrc`
  cooperation required).
- **Multi-monitor** aware — appears on the screen containing the mouse, or on
  the primary screen, your choice.
- **Customizable layout** — width, height, horizontal alignment, screen
  selection, font family/size, background opacity, slide-animation duration.
- **Live-apply** settings — most preferences take effect immediately; layout
  ones (size/position) on the next toggle.
- **Prompt pinned to bottom** of the panel (Guake-style), regardless of the
  panel's height.
- **Layout-agnostic shortcuts** — Control+letter shortcuts (`⌃R`, `⌃A`, `⌃E`,
  `⌃W`, …) work correctly on Cyrillic / Greek / non-Latin keyboard layouts.
- **Git badge** — floating pill in the top-right of the terminal shows the
  current branch plus `±N` files, `+X` insertions, `-Y` deletions when the
  working tree is dirty. Hidden outside git repos. Updates on `cd` and
  `git checkout` within ~1 second.
- **Clickable links** — `⌘`-hover highlights URLs in the buffer, `⌘`-click
  opens them. URLs go through `NSWorkspace.shared.open`; absolute or
  relative file paths are revealed in Finder instead of being launched in
  the default app.
- **Open at Login** toggle.

---

## Install / build

Requirements:

- macOS 13 or later
- Xcode 15+ (uses Swift 6 toolchain)

```sh
git clone <this repo>
cd shade
./Scripts/build.sh      # produces build/Shade.app
./Scripts/run.sh        # build + launch
swift test              # unit tests for pure modules
```

For everyday use:

```sh
cp -R build/Shade.app /Applications/
open /Applications/Shade.app
# then toggle "Open at Login" in Settings so the new bundle path is registered
```

The build script ad-hoc codesigns the bundle so the OS can prompt cleanly
for any future entitlements / permissions.

---

## Usage

### Toggle the panel

Default hotkey: **`F12`**.

> Note: on a stock Mac, the function-key row is mapped to media keys, so you
> may need to press `Fn+F12`. To make `F12` work standalone, enable
> *System Settings → Keyboard → Use F1, F2, etc. keys as standard function
> keys*, or just rebind in Shade's Settings to something like `Ctrl+\``.

Press `Esc` (or `F12` again) to hide.

### Tabs

| Action            | Shortcut           |
|-------------------|--------------------|
| New tab           | `⌘T`               |
| Close active tab  | `⌘W`               |
| Jump to tab N     | `⌘1` … `⌘9`        |
| Next tab          | `⌃Tab`             |
| Previous tab      | `⌃⇧Tab`            |

The tab bar lives at the bottom of the panel. Click a chip to switch, click
the `×` to close, click `+` for a new tab. Tab labels show the index and the
abbreviated current working directory (e.g. `1 · ~/projects/shade`).

Closing the last tab opens a fresh one — the panel always has at least one
live shell.

### Other shortcuts

| Action               | Shortcut    |
|----------------------|-------------|
| Toggle panel         | `F12`       |
| Hide panel           | `Esc`       |
| Open Settings        | `⌘,` (from the menu-bar icon) |
| Quit Shade           | `⌘Q` (from the menu-bar icon) |

`⌃R`, `⌃A`, `⌃E`, `⌃W`, `⌃U`, `⌃K`, … are all forwarded to the shell
unchanged — they work even when your keyboard layout is non-Latin
(Cyrillic, Greek, etc.).

---

## Configuration

### Via the Settings window

Open Settings from the menu-bar `▾` icon. Available sections:

- **Hotkey** — recorder for the toggle hotkey
- **Size** — width and height as a fraction of the screen
- **Position** — horizontal alignment (left/center/right) and target screen
- **Appearance** — monospace font family, size, background opacity
- **Startup** — open at login
- **Animation** — slide duration

Changes that affect the visible panel apply immediately; size/position changes
apply on the next toggle.

### Via `defaults` (CLI)

The Settings window is the easy path; for headless / dotfiles use the same
keys via `defaults`. Restart Shade or toggle the panel to apply.

```sh
# Layout
defaults write dev.shade.Shade widthFraction 0.6
defaults write dev.shade.Shade heightFraction 0.45
defaults write dev.shade.Shade horizontalAlignment center      # left | center | right
defaults write dev.shade.Shade screenChoice mouseLocation      # main | mouseLocation

# Appearance
defaults write dev.shade.Shade fontSize 14
defaults write dev.shade.Shade fontName "Menlo"                # "" = system monospaced
defaults write dev.shade.Shade backgroundOpacity 0.85          # 0.3 – 1.0

# Animation
defaults write dev.shade.Shade animationDuration 0.12          # 0.0 – 0.5 seconds

# Inspect / reset
defaults read dev.shade.Shade
defaults delete dev.shade.Shade
```

Hotkeys are stored separately by the KeyboardShortcuts library; rebind via
the Settings window.

---

## Releases

See [CHANGELOG.md](./CHANGELOG.md) for release notes.

## Recommended shell setup

Shade is a *terminal*, not a *shell* — features like ghost auto-completion
and reverse history search live in your shell config, not in Shade. A
sensible baseline for zsh:

```sh
# Ghost suggestions (greyed-out completion of past commands, right-arrow to accept)
brew install zsh-autosuggestions
echo 'source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh' >> ~/.zshrc

# Syntax highlighting (commands turn red if not on PATH, etc.)
brew install zsh-syntax-highlighting
echo 'source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh' >> ~/.zshrc

# Fuzzy history search (Ctrl-R powerhouse replacement)
brew install fzf
$(brew --prefix)/opt/fzf/install
```

For dynamic tab titles to react instantly on `cd` (instead of waiting on
Shade's 1-second poll), you can also add:

```sh
# In ~/.zshrc — emits OSC 7 + OSC 0 on every prompt
precmd() { print -Pn "\e]7;file://${HOST}${PWD}\a\e]0;%~\a" }
```

---

## Troubleshooting

**`F12` does nothing.** macOS may be intercepting it as a media key. Either
press `Fn+F12`, flip *System Settings → Keyboard → Use F1, F2, etc. keys as
standard function keys*, or rebind to e.g. `Ctrl+\`` in Shade's Settings.

**Hotkey works once, then stops after moving the app.** SMAppService
remembers the absolute path of the bundle that registered itself. If you
moved `Shade.app` (e.g. into `/Applications`), toggle *Open at Login* off
and on again to re-register.

**Prompt appears in the middle of the panel, not the bottom.** The terminal
view computes its row count after layout. Shade primes the panel frame at
launch and resolves layout before the shell starts — if you ever see this,
file an issue with the screen geometry and font size.

**Ctrl+R does nothing on a non-Latin layout.** Shade re-implements
control-letter shortcuts using the physical keyCode rather than the
characters produced by the current input source. If a particular shortcut
still misbehaves, check `KeyCodes.swift` — the ANSI map covers letter rows
A–Z by default; non-letter rows are forwarded to SwiftTerm unmodified.

**New tabs open in `/` instead of `~`.** GUI apps launched via
LaunchServices start with `cwd = /`. Shade `chdir`s to `$HOME` at launch so
spawned shells inherit it — if you still see `/`, you launched the
executable directly (e.g. for debugging) rather than via the `.app` bundle.

---

## Architecture

```
Sources/Shade/
├── ShadeApp.swift           @main + AppDelegate (menu bar, hotkey, panel wiring)
├── BranchBadge.swift        Floating git branch + status pill (SwiftUI)
├── DropdownPanel.swift      NSPanel: borderless, floating, slide-in animation
├── GitInfo.swift            Branch from .git/HEAD, status via git subprocess
├── HotkeyManager → removed (replaced by KeyboardShortcuts library)
├── Hotkeys.swift            KeyboardShortcuts.Name declarations (toggleShade)
├── KeyCodes.swift           Layout-agnostic keyCode → ASCII mapping
├── Preferences.swift        UserDefaults-backed settings struct + screen/frame resolution
├── ProcessCwd.swift         libproc-based CWD lookup for shell processes
├── SettingsWindow.swift     SwiftUI Settings view + NSWindowController
├── TabBar.swift             SwiftUI TabBarView + TabsObservable
├── TerminalSession.swift    Wrapper around SwiftTerm.LocalProcessTerminalView
└── TerminalsController.swift Owns multi-tab sessions, swaps view on selection
```

Key design choices:

- **SwiftPM, not Xcode project.** Sources, `Package.swift`, `Resources/Info.plist`,
  and a small bash script in `Scripts/build.sh` package everything into a
  bundle. Source-only, plain text, easy to grep / diff.
- **Borderless `NSPanel`**, no `.nonactivatingPanel`. The app activates fully
  when the panel is shown so that `⌘`-shortcuts route to us instead of
  leaking to whichever browser was last focused.
- **`performKeyEquivalent` + `sendEvent` override** in `DropdownPanel`.
  `performKeyEquivalent` catches `⌘`-tab-shortcuts; `sendEvent` translates
  Control+letter into the canonical control byte using the physical keyCode
  (works on any layout) and writes it directly into the active session's PTY.
- **Live-apply prefs.** `SettingsModel.save()` posts
  `.shadePreferencesChanged`; `AppDelegate` re-applies to the panel and
  every session so font/opacity changes are instant.
- **Prime-then-start.** The panel's frame is set off-screen at launch and
  layout is resolved before the first shell starts, so SwiftTerm knows its
  rows count and `padCursorToBottom()` pins the prompt to the bottom of the
  panel from the very first prompt.

---

## Dependencies

- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) — VT100 / xterm
  terminal emulator + local PTY shell hosting. **Vendored** under
  `Vendor/SwiftTerm/` so we can expose `linkHoverColor` (upstream hardcodes
  the link underline to the cell's foreground color, which is unreadable
  on a translucent background). All other behavior is unchanged from
  upstream.
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) —
  global hotkey registration with a SwiftUI recorder UI.

Both are pinned via Swift Package Manager (`Package.swift`) and both are MIT
licensed, the same as Shade. Full license texts: [THIRDPARTY.md](./THIRDPARTY.md).

---

## License

[MIT](./LICENSE) — © 2026 Anton Rudakov.

Third-party components retain their respective licenses; see
[THIRDPARTY.md](./THIRDPARTY.md).

---

## Project layout

```
shade/
├── Package.swift            SwiftPM manifest
├── Resources/Info.plist     LSUIElement = true, bundle metadata
├── Scripts/
│   ├── build.sh             swift build → wrap into Shade.app → ad-hoc codesign
│   └── run.sh               build + open
├── Sources/Shade/           Swift sources (see Architecture)
└── README.md                this file
```
