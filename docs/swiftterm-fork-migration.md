# SwiftTerm fork maintenance

_Status: SwiftTerm 1.99.1 migration complete, merged into `main` and released
in Shade 0.1.25. The four specific patches were approved and published on
2026-10-23._

## Current state

The dependency is upstream release `v1.99.1`
(`2f573f73af5e768d90847dce20c97fa9535d7164`) plus four approved feature commits
and a follow-up link-background fix, ending at
`850f6469329bada193981efa8a7e6ccd3920792e`. The fork preserves
it on published branch `shade/update-1.99.1` and tag `shade-pin-2026-10-23-r2`.
`Package.swift` and `Package.resolved` pin that same published full revision.
See [the migration audit](swiftterm-1.99.1-update.md) for the approval scope,
exact commits and verification results.

The previous pin was `c665309f8fb31ad3600c93aa3a957b573e964dd2`, based on
upstream `c74d1e6`, with only the link-highlight patch. The new upstream API
requires the additional narrow commands to preserve existing Shade behavior.

SwiftTerm 1.99.1 no longer exposes mutable `Terminal`, `BufferLine` or
`SelectionService` through its view. Shade uses copied content/input snapshots,
`observeOscEvents`, `setProcessOutputHandler`, and narrow lock-protected view
commands. Shell integration, prompt history, command timing, notifications,
preferences and shortcut routing remain in Shade.

## Patch inventory

| Patch | Current owner | Decision |
|---|---|---|
| Configurable link-highlight color + cell tint | SwiftTerm fork | **Keep** — public `linkColor` changes text/underline only; renderer runs and wrapped link ranges remain private |
| Atomic keyboard selection | SwiftTerm fork | **Restore as a value command** — the old public selection service is now internal; mutation must share the parser lock |
| Local clear preserving input/parser state | SwiftTerm fork | **Move behind a view command** — snapshots cannot mutate rows, and feeding local escapes can interrupt PTY parsing |
| Parser-time OSC geometry and generation | SwiftTerm fork | **Keep copied context** — asynchronous delivery cannot recover a previous scroll offset, buffer or width generation |
| OSC parsing and PTY chunk splitting | Upstream | **Drop Shade parser** — passive copied OSC observation preserves built-in handling |
| Prompt history and output extraction | Shade | **Keep** — copied bounded snapshots and parser-time events are sufficient |
| Read-only cut | Shade + upstream public API | **Keep** — `getSelection()` and `selectNone()` remain public |
| Metal warning cleanup | Upstream unchanged | **Dropped** — cosmetic warnings do not justify a fork patch |
| CoreGraphics dirty-region fix | Upstream | **Dropped** — merged as SwiftTerm #582 |
| Wheel → xterm button 4/5 | Upstream | **Dropped** — upstream implementation is a strict superset |

## Patch policy

Treat every SwiftTerm modification as a last resort:

1. First test whether the behavior can be implemented in Shade through public
   API, configuration, delegates, subclassing or composition.
2. A fork patch is acceptable only when the feature cannot be implemented
   correctly at the app layer.
3. Get explicit user approval for each new or changed SwiftTerm patch.
4. Keep each accepted patch as one focused commit with focused tests.
5. Do not mix warning cleanup, formatting or unrelated upstream fixes into the
   fork delta.

The audit documents why each retained command or render hook cannot be
implemented correctly through the new public view API. No mutable terminal
reference or escaping locked closure is exposed by these patches. Shade uses
CoreGraphics; enabling Metal still requires a separate visual audit.

## Upstream sync procedure

1. Fetch and intentionally choose a tagged upstream release or `upstream/main`.
2. Re-audit every remaining patch against new public APIs. Drop anything that
   upstream implemented or Shade can now own; obtain approval for specific
   new or changed fork patches.
3. Keep each patch in a focused commit and run the complete SwiftTerm test suite.
4. Publish the candidate fork branch and tag it as `shade-pin-YYYY-MM-DD`.
5. Update the revision in Shade's `Package.swift`, then run
   `swift package resolve` so `Package.resolved` records the same SHA.
6. Remove editable dependency overrides, run Shade's complete test suite and
   release packaging checks against the published revision.

Never commit a remote revision before it has been pushed: an editable local
dependency can hide a broken pin.

## Verification checklist

- [x] Full SwiftTerm run: approved-patch tests pass; one pre-existing Kitty
  Ctrl-/ test assumes a US layout and fails under RussianWin
- [x] `swift test` in Shade: 346 tests pass from a fresh build directory using
  the published pin without editable overrides
- [x] `swift test -c release` in Shade: all 346 tests pass with optimizations
- [x] `make test-build`: release bundle, signature, resources and packaging fixtures

These former manual checks are now covered by automated Shade tests against
the pinned fork (they exercise the terminal view and session, not keyboard
delivery through a running app):

- [x] keyboard selection: character, word, wide glyph, emoji and soft wrap —
  `TerminalKeyboardSelectionTests`; BiDi movement is covered by the fork's
  keyboard-selection regressions
- [x] selection starts at the live cursor while the viewport is scrolled up —
  `TerminalKeyboardSelectionTests.testSelectionStartsAtTheLiveCursorWhileScrolledUp`
- [x] `⌘X` copies the selection, clears it and sends one DEL per selected
  character — `TerminalClipboardTests`; the Cut menu action reaching the
  keyboard controller — `AppDelegateWiringTests`
- [x] OSC 133 navigation (`⌘⇧↑` / `⌘⇧↓`) and output copy (`⌘⇧O`) —
  `TerminalClipboardTests.testPromptNavigationAndOutputCopyFollowOSC133Marks`;
  the `⌘⇧O` key event through the panel's key handler —
  `AppDelegateWiringTests.testCopyOutputShortcutUsesTheDelegatePasteboard`
- [x] OSC 133 split across PTY chunks and multiple marks in one chunk —
  `TerminalOscObservationTests`
- [x] OSC 133 rows remain correct after scrollback trimming —
  `TerminalPromptHistoryTests.testMarksTrimmedOutOfScrollbackAreDroppedAndNotNavigated`

These remain manual checks in a running application, because they judge what
is drawn on screen:

- [ ] configurable link tint on `⌘`-hover (the configured color reaching the
  view is tested in `TerminalSessionAppearanceTests`)
- [ ] rendering and translucency in nano, vim, less and htop

## Historical note

Shade originally vendored an edited SwiftTerm checkout under
`Vendor/SwiftTerm`. The 2026-07-02 migration reconstructed those edits as
feature commits on a rebase-tracked fork and replaced the vendor directory with
a normal SwiftPM dependency. The first fork pin was
`87eb734e9a2e866f8a5c50945a58837a935b08e4`, tagged
`shade-pin-2026-07-02`.

The initial fork carried keyboard selection, link styling, read-only cut,
OSC 133 accessors and a Metal warning cleanup. That inventory is retained here
only as history; it is not the current architecture.

## References

- Fork: https://github.com/tavvet/SwiftTerm
- SwiftTerm renderer fix: [#582](https://github.com/migueldeicaza/SwiftTerm/pull/582)
- Initial vendor commit in Shade: `9822b33`
