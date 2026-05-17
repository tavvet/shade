# Shade

Drop-down terminal for macOS — Guake/Yakuake-style. Native Swift, keyboard-first, with tabs.

## Status

Early development. MVP phase 1: single tab, F12 toggle, slide-from-top animation.

## Build & run

```sh
./Scripts/build.sh   # produces build/Shade.app
./Scripts/run.sh     # build, then open the app
```

Press `F12` to toggle the terminal (rebind in Settings…). Press `Esc` to hide.

## Settings

No GUI yet — configure via standard `defaults`. Restart Shade after changes, or just toggle the panel (settings reload on every show).

```sh
# Width as a fraction of the screen (0.1 – 1.0). Default: 1.0
defaults write dev.shade.Shade widthFraction 0.5

# Height as a fraction of the screen (0.1 – 1.0). Default: 0.4
defaults write dev.shade.Shade heightFraction 0.45

# Horizontal alignment: left | center | right. Default: center
defaults write dev.shade.Shade horizontalAlignment center

# Which screen the dropdown appears on: main | mouseLocation. Default: mouseLocation
defaults write dev.shade.Shade screenChoice mouseLocation

# Font: size (9–22 pt) and family. Family "" = system monospaced.
defaults write dev.shade.Shade fontSize 14
defaults write dev.shade.Shade fontName "Menlo"

# Background opacity (0.3 – 1.0). Default: 0.94
defaults write dev.shade.Shade backgroundOpacity 0.85

# Slide animation duration in seconds (0.0 – 0.5). Default: 0.16
defaults write dev.shade.Shade animationDuration 0.12

# Inspect current values
defaults read dev.shade.Shade

# Reset everything
defaults delete dev.shade.Shade
```

Changes made via the GUI (Settings… in the menu bar) apply instantly. Changes made via `defaults write` apply on the next `F12` toggle.

## Stack

- Swift 6 + SwiftUI/AppKit
- SwiftPM for sources; custom bash script bundles the executable into `.app`
- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) for VT100/xterm emulation
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) for the global hotkey + recorder UI
