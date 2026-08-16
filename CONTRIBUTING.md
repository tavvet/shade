# Contributing to Shade

Thanks for the interest. Shade is a small focused tool — contributions that
make it more reliable, more native to macOS, or close gaps from Guake /
Yakuake / iTerm2 are very welcome.

## Setup

Requirements:

- macOS 13 or later (development tested on macOS 15)
- Xcode 16+ (Swift 6 toolchain)

```sh
git clone <fork-url>
cd shade
make            # → build/Shade.app
make run        # build + launch
```

The project uses Swift Package Manager — there is no `.xcodeproj`. You can
open `Package.swift` directly in Xcode if you prefer the IDE.

## Development workflow

A lightweight pipeline for landing a feature. Scale it to the change — small,
obvious fixes can skip straight to the implementation step.

1. **Plan (non-trivial features).** Sketch the design before coding: which files
   change, whether it needs a new SwiftTerm fork API, the edge cases and
   risks. The [ROADMAP](ROADMAP.md) tags items S / M / L; M and L are worth a
   plan, S usually isn't.
2. **Implement.** Work on a feature branch, one logical change per commit. Keep
   `swift test` and `swift build -c release` green as you go.
3. **Review & fix.** Re-read the diff critically before merging — correctness
   first, then simplification. Give extra scrutiny to anything touching the PTY,
   concurrency (`@MainActor` boundaries), or AppKit lifecycle, then apply the
   fixes.
4. **Verify.** Run the automated checks (`swift test` plus a release build, both
   enforced by CI) and exercise the new behavior in a real `Shade.app` — there are
   no UI tests, so manual confirmation matters.
5. **Update docs.** Keep documentation in step with the change: the
   [README](README.md) (feature list, Architecture tree, shortcut tables),
   `CHANGELOG.md` under `[Unreleased]`, any matching [ROADMAP](ROADMAP.md) entry,
   and the `integrations/` snippets if they're affected.
6. **Merge.** Open a PR — see [Before you open a PR](#before-you-open-a-pr) for
   the pre-merge checklist — and land one logical change at a time. Releases are
   cut from the accumulated `[Unreleased]` entries.

## Before you open a PR

- `swift test` passes (CI runs this on every push).
- `swift build -c release` passes cleanly (no warnings introduced).
- `make build` produces a working `Shade.app`.
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
- Scalar user-facing settings extend the `Preferences` value model, persist
  through `PreferencesStore`, and get a control on the appropriate settings
  page. Structured collections with their own lifecycle (such as saved SSH
  profiles) use a dedicated model and store instead of `UserDefaults`.
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
