# SwiftTerm fork maintenance

_Status: active. Initial de-vendoring completed 2026-07-02; the patch set was
re-audited and minimized on 2026-08-18._

## Current state

Shade uses a revision-pinned
[SwiftTerm fork](https://github.com/tavvet/SwiftTerm) rebased on upstream. The
2026-08-18 audit reduced the fork from five local patches to exactly one:

- configurable link-highlight color and cell tint;
- fork commit: `c665309` on top of upstream `c74d1e6`, published on fork
  `main` and pinned by Shade.

`Package.swift` and `Package.resolved` both pin the published full revision
`c665309f8fb31ad3600c93aa3a957b573e964dd2`, so a fresh clone does not depend
on the maintainer's editable checkout.

All app-specific behavior now lives in Shade:

- keyboard selection uses public `SelectionService`, `BufferLine` and terminal
  lookup APIs;
- OSC 133 is observed in `ActivityTerminalView` without replacing SwiftTerm's
  built-in semantic handler;
- cut uses upstream `getSelection()` and `selectNone()`;
- prompt history uses `Buffer.totalLinesTrimmed`, `buffer.yDisp`,
  `getScrollInvariantLine(row:)` and the view's own scroll clamping.

## Patch inventory

| Patch | Current owner | Decision |
|---|---|---|
| Configurable link-highlight color + cell tint | SwiftTerm fork | **Keep** — link ranges, renderer attributes and their cache are private to SwiftTerm |
| Keyboard text selection | Shade (`TerminalKeyboardSelection`) | **Moved out** — public selection and buffer APIs are sufficient |
| OSC 133 cursor/event observation | Shade (`OSC133StreamObserver`) | **Moved out** — the open PTY view is a correct composition point |
| `⌘X` selection access/clear helpers | Shade + upstream public API | **Dropped** — `getSelection()` and `selectNone()` replace them |
| OSC scrollback accessors | Shade + upstream public API | **Dropped** — public buffer geometry is sufficient |
| Metal `withUnsafeBytes` warning-silence | Upstream unchanged | **Dropped** — cosmetic warnings do not justify a fork patch |
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

The link-highlight patch passes this rule because Shade cannot obtain the full
wrapped link range or inject attributes into both renderer paths through public
API. An overlay would duplicate private renderer geometry and caching.

## Upstream sync procedure

1. Fetch upstream and rebase the fork branch on `upstream/main`.
2. Re-audit every remaining patch against new public APIs. Drop anything that
   upstream implemented or Shade can now own.
3. Run the complete SwiftTerm test suite.
4. Push the rebased fork tip and tag it as `shade-pin-YYYY-MM-DD`; the tag keeps
   the revision reachable if the branch is rebased again.
5. Update the revision in Shade's `Package.swift`, then run
   `swift package resolve` so `Package.resolved` records the same SHA.
6. Run Shade's complete test suite and release build.

Never commit a remote revision before it has been pushed: an editable local
dependency can hide a broken pin.

## Verification checklist

- [x] `swift test` in SwiftTerm
- [x] `swift test` in Shade
- [x] `make build`
- [ ] keyboard selection: character, word, wide glyph, emoji, BiDi and soft wrap
- [ ] selection starts at the live cursor while the viewport is scrolled up
- [ ] `⌘X` copies selection and clears it
- [ ] OSC 133 navigation (`⌘⇧↑` / `⌘⇧↓`) and output copy (`⌘⇧O`)
- [ ] OSC 133 split across PTY chunks and multiple marks in one chunk
- [ ] OSC 133 rows remain correct after scrollback trimming
- [ ] configurable link tint on `⌘`-hover
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
