# Contributing to Shade

Thanks for the interest. Shade is a small focused tool — contributions that
make it more reliable, more native to macOS, or close gaps from Guake /
Yakuake / iTerm2 are very welcome.

## Setup

Requirements:

- macOS 13 or later (development tested on macOS 15)
- Xcode 15+ (Swift 6 toolchain)

```sh
git clone <fork-url>
cd shade
./Scripts/build.sh      # → build/Shade.app
./Scripts/run.sh        # build + launch
```

The project uses Swift Package Manager — there is no `.xcodeproj`. You can
open `Package.swift` directly in Xcode if you prefer the IDE.

## Before you open a PR

- `swift test` passes (CI runs this on every push).
- `swift build -c release` passes cleanly (no warnings introduced).
- `./Scripts/build.sh` produces a working `Shade.app`.
- New behavior is exercised manually — describe what you tested in the PR
  description (we don't have UI tests yet).
- One logical change per PR. Refactors that mix with feature work are hard
  to review; please split them.

## Coding style

- Follow [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)
  and match the surrounding code's style.
- Default to writing no comments. Add them only when the *why* is non-obvious
  (a hidden constraint, an Apple-API quirk, a workaround for a specific bug).
- `@MainActor` everywhere AppKit / SwiftUI is touched. Concurrency boundaries
  use `nonisolated` + `MainActor.assumeIsolated` (see existing examples).
- New user-facing settings go through `Preferences` (UserDefaults) and get a
  control in `SettingsWindow.swift`.
- Pure logic (parsers, models, layout math) belongs in a module that's already
  covered by `Tests/ShadeTests/` — add a test alongside the change.

## Reporting bugs

Use the *Bug report* template. Please include:

- macOS version + chip (Intel / Apple Silicon)
- Build / commit SHA
- Active keyboard layout(s) — several past bugs have been layout-specific
- Steps to reproduce

## Licensing

Shade is MIT licensed. By contributing, you agree to release your changes
under the same license.
