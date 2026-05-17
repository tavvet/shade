# Shade

Drop-down terminal for macOS — Guake/Yakuake-style. Native Swift, keyboard-first, with tabs.

## Status

Early development. MVP phase 1: single tab, F12 toggle, slide-from-top animation.

## Build & run

```sh
./Scripts/build.sh   # produces build/Shade.app
./Scripts/run.sh     # build, then open the app
```

Press `F12` to toggle the terminal. Press `Esc` to hide.

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

# Inspect current values
defaults read dev.shade.Shade

# Reset everything
defaults delete dev.shade.Shade
```

## Stack

- Swift 6 + SwiftUI/AppKit
- SwiftPM for sources; custom bash script bundles the executable into `.app`
- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) for VT100/xterm emulation
- Carbon `RegisterEventHotKey` for the global hotkey
