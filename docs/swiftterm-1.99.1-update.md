# SwiftTerm 1.99.1 update

Status: complete. The four specific fork changes were approved, implemented and
published on 2026-10-23. Shade pins the published revision; all 346 Shade tests
and `make test-build` passed from a fresh standard build directory without an
editable dependency override.
Shade branch: `update/swiftterm-1.99.1`.

## Target

- Upstream release: `v1.99.1`.
- Reviewed revision: `2f573f73af5e768d90847dce20c97fa9535d7164`.
- Minimum build toolchain: Swift 6.2; CI must select a compatible Xcode explicitly.

## Changes that can remain in Shade

- Replace `getTerminal().rows/cols` with copied `terminalDimensions`.
- Use `setProcessOutputHandler` for background-tab activity, forwarding only
  a notification to the main actor. The PTY adapter now bypasses the view's
  `dataReceived` override.
- Use `observeOscEvents` instead of splitting PTY chunks in Shade. Keep the
  observation token alive and dispatch copied events to the main actor in order.
- Extract completed command output from bounded `terminalContentSnapshot`
  values, joining soft wraps while retaining hard line breaks.
- Keep shell lifecycle, command timing, notifications, preferences and shortcut
  routing in Shade.

## Approved fork changes

### 1. Preserve configurable link underline and background tint

Retain the existing `linkHighlightColor` behavior in the new snapshot renderer:
the configured underline color and a 35% blend into the original cell
background, without replacing the cell's foreground color. Carry the color
through the frame appearance and snapshot cache identity.

Public `linkColor` changes text and underline color only. Neither the attributed
run builder nor its URL attributes are public composition points, and a view
overlay cannot reproduce wrapped/BiDi link ranges and renderer cache behavior.

### 2. Provide an atomic keyboard-selection command

Add a value-based view command to extend selection by character, word, vertical
row, or line boundary. Execute cursor anchoring, bounds checks, wide-cell
normalization and the selection mutation under the terminal lock. Return copied
selection coordinates for inspection; do not expose mutable `Terminal`,
`BufferLine`, `SelectionService`, or an escaping locked closure.

On macOS, public selection APIs only expose selection text, active state,
select-all and select-none. `TerminalView.selection` is internal. Search and
mouse event synthesis cannot express the existing cursor-anchored keyboard
selection reliably, particularly with scrollback, soft wraps and wide glyphs.

### 3. Provide a local clear-previous-output command

Move the existing Shade buffer operation behind a narrow view command. Under
the terminal lock, clear rows above the current logical input, preserve the
cursor and multiline semantic prompt, leave the alternate screen alone, and
schedule a redraw. Do not feed escape sequences or send bytes to the PTY.

Public `clearScrollback` does not clear the previous visible output. Feeding an
erase sequence can interrupt an unfinished PTY escape sequence and cannot
preserve the existing multiline prompt semantics. Copied snapshots are read-only.

### 4. Include parser-time geometry in copied OSC events

Extend the copied OSC event context with scroll-invariant cursor coordinates,
active-buffer identity and dimensions captured at the parser boundary. Include
a geometry generation in the relevant copied state so Shade can reject marks
that predate a resize or local clear even when the width later returns to its
old value.

The existing event contains only screen-relative cursor coordinates. Its
asynchronous callback cannot recover the original scrollback offset or buffer:
the same PTY batch can scroll, resize or switch to the alternate screen before
delivery. A later content snapshot therefore cannot supply equivalent context.

## Verification before updating the published pin

- Keep each approved fork change in a focused commit with regression tests.
- Run the complete SwiftTerm test suite.
- Cover selection of wide glyphs, emoji and BiDi text, word movement across soft
  wraps, stale mouse modes, scrollback bounds and live-cursor anchoring.
- Cover local clear with pending shell input and a partially received escape
  sequence; verify no PTY bytes are sent.
- Cover multiple OSC marks in one batch, a same-batch alternate-screen switch,
  split UTF-8 payloads, scrollback trimming and width round trips.
- Run Shade's complete tests and release packaging checks with the published
  immutable dependency revision.

## Baseline verification on 2026-10-23

Unmodified upstream `v1.99.1` builds with local Swift 6.4 using native SwiftPM.
The complete run executed 1,659 tests and reported three failures:

- `controlSlashKeepsItsCodepointWithKittyKeyboardProtocol`: the generated CSI
  contains code point 46 instead of the expected 47. This also fails in an
  isolated rerun; its relationship to the active keyboard layout needs review.
- `aTimeoutClearsTheBarAfterItsOwnSilence` and `eachReportRestartsTheWait`:
  progress-bar visibility expectations fail under the full parallel workload.
  All nine progress-timeout tests pass in the focused rerun.

Logs: `/private/tmp/shade-swiftterm-upstream-baseline.log` and
`/private/tmp/shade-swiftterm-upstream-focused.log`. These are pre-existing
upstream/local-environment results, before any migration or fork edits.

## Implementation verification

The fork contains four approved feature commits on `v1.99.1` and their review fix:

| Commit | Change |
| --- | --- |
| `0181558` | Configurable link underline and background tint |
| `09180d1` | Atomic keyboard-selection commands and 13 movement regressions |
| `4d3f1d7` | Local clear command and 6 parser/input preservation regressions |
| `df19756` | Copied OSC geometry, generation, timestamp and 4 geometry regressions |
| `850f646` | Mark tinted link backgrounds for actual renderer fills and test flag removal |

The full candidate revision is
`850f6469329bada193981efa8a7e6ccd3920792e`. It is preserved in the local
`/Volumes/fury/projects/SwiftTerm` repository on `shade/update-1.99.1` and by
the annotated tag `shade-pin-2026-10-23-r2`; both were atomically pushed to origin.
The original `shade-pin-2026-10-23` tag is preserved unchanged.
Its existing `main` is unchanged.

- SwiftTerm: all 149 XCTest cases passed; 1,665 Swift Testing cases ran with
  only the previously observed Kitty Ctrl-/ failure. The active input source
  is `com.apple.keylayout.RussianWin`, while that fixture assumes US input.
  Both progress-timeout tests passed in this full run.
- Shade: all 346 tests passed. They exercise copied history values, actual hidden PTY activity,
  split OSC/UTF-8, C1 ST, same-batch buffer switches, delayed marks after a
  width round trip and copying across soft-wrap spaces.
- Release `make test-build` passed against the published revision: app creation, signature, metadata, resources
  and packaging failure fixtures. SwiftTerm now embeds shader source in Swift,
  so only KeyboardShortcuts needs a resource bundle and accessor overlay.
- CI explicitly selects Xcode 26.3 and the native SwiftPM backend. The package
  manifest now declares Swift tools 6.2.

The initial checks used a local editable dependency in a separate scratch
directory. The final manifest and lockfile use the published SHA, and final
checks run from a new standard `.build` directory without editable overrides.
The previous build cache was preserved under
`build/swiftpm-cache-before-update-20261023` because its git alternates still
pointed to the repository's former filesystem location.

## Review corrections

- Closing a terminal during SwiftTerm's post-exit output drain now requires a
  positive shell PID before any process/group query or signal. Three tests use
  real child lifecycle states and recorded signal calls: an exited child with
  pending output sends no signal, a live shell targets its own process group,
  and a failed group signal falls back only to the positive shell PID.
- The link tint fix marks custom link backgrounds as explicit, so both renderer
  background passes draw them even when the original cell used the default
  background. Tests verify that ordinary cells keep the default behavior and
  disabling tint removes the explicit-background flag.
- Fork pin `850f6469329bada193981efa8a7e6ccd3920792e` is published under
  `shade-pin-2026-10-23-r2`. The original tag remains unchanged.
- A subsequent app check exposed an optimized-build failure in Shade's SSH
  validation: passing `CharacterSet.controlCharacters.contains` as a bound
  predicate falsely rejected ordinary names. An explicit closure fixes the
  failure without changing validation rules or persisted data. The supplied
  connections file loads successfully through the production disk queue and
  controller, and all 346 tests pass in release mode. CI now runs both debug
  and release unit tests; the temporary diagnostic using the supplied file
  was removed from the test target.
