# SwiftTerm 1.99.3 candidate

Status: prepared for review and manual acceptance. Not merged or released.

## Revisions and scope

- Upstream `v1.99.3`: `282c3c3a932b55c129628876b70f37d993af1615`.
- Published fork branch: [shade/update-1.99.3](https://github.com/tavvet/SwiftTerm/tree/shade/update-1.99.3).
- Immutable Shade pin: `e4c48d78035485cf5cc2d2986243156ac3e47703`.
- Previous published pin: `850f6469329bada193981efa8a7e6ccd3920792e`.

The owner approved adapting the existing link tint and completing compatibility
fixes. No additional fork feature is introduced. The four focused commits are:

| Commit | Patch |
| --- | --- |
| `473f923` | Atomic keyboard-selection commands, unchanged |
| `efa16ad` | Local clear without feeding parser bytes, unchanged |
| `1fa35f6` | Parser-time OSC geometry and generation, unchanged |
| `e4c48d7` | Link tint adapted to the upstream underline API |

The adapted link patch retains the 35% cell-background blend, explicit fill flag
and appearance/native-color/attribute-cache invalidation. The upstream
`linkUnderlineColor` takes precedence; absent an explicit override, the existing
Shade highlight color supplies the underline. Selection continues to win over
link text/underline. The upstream contrast policy still applies. Tinted links
use the shaped rendering path rather than silently losing their background in
the Metal plain-row optimization.

The public underline API removes the need for a separate fork underline
renderer override. Background tint still requires access to private renderer
runs, so the remaining fork patch cannot be replaced with a view overlay.

## Shade compatibility fixes

- Replace seven obsolete test-only `dataReceived(slice:)` injections in four
  test files with the equivalent public `feed(byteArray:)`. SwiftTerm now marks
  the former method unavailable because real PTY output bypasses it. Production
  Shade output observation already uses `setProcessOutputHandler`.
- Preserve SwiftPM's exact product-path spelling in the resource VFS mapping
  and its cache identity. Foundation normalized `/private/tmp` to `/tmp`, making
  the old overlay miss compiler inputs and causing the packaged app to depend
  on its developer build directory.
- Exercise the new public link-request API through protocol dispatch: HTTP,
  HTTPS, explicit file URL, and detected absolute directory. These tests capture
  and resolve the callback without launching another app. The legacy Shade
  delegate remains supported; upstream now checks links before forwarding.

## Verification

Validation uses native SwiftPM on macOS with Swift 6.4.2. Shade is resolved from
its published remote SHA in a fresh standard `.build` directory, without an
editable dependency or local-path override.

- SwiftTerm final retained suite: 160 XCTest cases pass; 1,966 Swift Testing
  cases execute with only `controlSlashKeepsItsCodepointWithKittyKeyboardProtocol`
  failing under RussianWin (codepoint 46 instead of 47). The same failure is
  reproduced on untouched `v1.99.3` under the same layout.
- Earlier parallel runs exposed intermittent cursor-blink/headless timeout
  fixtures. Focused reruns pass; the final serial run has neither timeout.
- Added tint/underline coexistence, dynamic appearance, selection precedence,
  shaped-path fallback and actual CoreGraphics tint-on/tint-off pixel checks.
- An offscreen CoreGraphics preview was inspected. This is not a live app,
  editor or keyboard-event acceptance test.
- Shade debug: all 465 tests pass, including the four new delegate cases.
- Shade release: all 465 tests pass with optimizations.
- `make test-build`: passes release packaging, ad-hoc signature, metadata,
  licenses/resources, resource access with the build tree hidden, and packaging
  failure fixtures.

## Manual acceptance

Use the review branch, not `main`, and keep the existing installed Shade app.
In a separate checkout:

```sh
git switch update/swiftterm-1.99.3
swift package resolve
swift test --build-system native
swift test --build-system native -c release
make test-build
```

Quit the existing Shade instance before launching the candidate:

```sh
open build/Shade.app
```

The candidate has the same bundle identity and uses normal Shade preferences.
It is not an isolated profile. Do not copy it into `/Applications` until accepted.

1. Hover links with Command held. Check custom underline/background tint,
   unchanged foreground, wrapped links, changing highlight color and selecting
   across the link. Test ordinary URLs and local-file reveal behavior. Expect
   upstream safety checks for custom schemes and unsafe local targets.
2. Exercise keyboard selection by character/word/line, emoji, wide glyphs and
   wrapped rows, including while scrolled into history. Check Cut and clipboard.
3. Check OSC 133 prompt navigation (`⌘⇧↑` / `⌘⇧↓`) and output copy (`⌘⇧O`),
   after resize and with long scrollback. Clear previous output with a partially
   entered or multiline command; input must remain intact.
4. Run nano, vim, less and htop. Check cursor, redraw, scrolling, alternate-screen
   return, colors and translucency at normal and reduced opacity.
5. Open/close tabs and background sessions, then quit/restart the candidate.

After review, publication/merge/release remain separate actions. If rejected,
quit the candidate and reopen the unchanged installed app. No settings migration
or installed-app replacement is part of this upgrade branch.
