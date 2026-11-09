# SwiftTerm 1.99.3 candidate

Status: prepared for review and manual acceptance. Not merged or released.

## Revisions and scope

- Upstream `v1.99.3`: `282c3c3a932b55c129628876b70f37d993af1615`.
- Published fork branch: [shade/update-1.99.3](https://github.com/tavvet/SwiftTerm/tree/shade/update-1.99.3).
- Immutable Shade pin: `1e0a29a3579917b029e02a0e07ace99674b9cd63`.
- Previous published pin: `850f6469329bada193981efa8a7e6ccd3920792e`.

The owner approved adapting the existing link tint, then separately approved
the Swift 6.2 compatibility fix and trusted-link-directory hook. The original
keyboard-selection, clear-output and OSC geometry patches are unchanged.
The focused commits are:

| Commit | Patch |
| --- | --- |
| `473f923` | Atomic keyboard-selection commands, unchanged |
| `efa16ad` | Local clear without feeding parser bytes, unchanged |
| `1fa35f6` | Parser-time OSC geometry and generation, unchanged |
| `e4c48d7` | Link tint adapted to the upstream underline API |
| `67d31e9` | Materialize the Powerline flame-path slice for Swift 6.2 |
| `b70b3b6` | Trusted local-directory fallback for checked links |
| `af68390` | Explicit callback sendability |
| `1e0a29a` | Final callback accessor avoids inherited ABI mismatch |

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

## Swift 6.2 compiler compatibility

The first PR build on Xcode 26.3 / Swift 6.2.4 rejected the unmodified upstream
Powerline flame-path array concatenation. The owner separately approved
materializing `flameLowerPath.dropFirst()` with `Array(...)`. The segment order
and rendering geometry are unchanged. This cannot be fixed through a Shade
view API because compilation fails inside the dependency. Focused Powerline
checks (16 XCTest and 3 Swift Testing tests) pass locally; CI verifies Swift 6.2.

## Trusted link-directory fallback

The new upstream checked-link bridge resolves paths before Shade's legacy
callback. Without OSC 7, a shell-relative file was either blocked or, when the
application directory contained the same basename, incorrectly replaced by that
application-directory file. A safe activation reproducer confirmed both cases.

The owner separately approved a narrow macOS `linkFallbackDirectoryProvider`
API. It runs outside the terminal lock at link-check time, only if shell-directory
resolution is enabled and OSC 7 has no usable base. A valid absolute trusted
local path supplies the base. A configured provider returning nil or an invalid
path blocks detected filesystem paths rather than falling back to the app cwd.
No provider preserves upstream defaults. Local OSC 7 remains authoritative and
remote OSC 7 remains blocked. URL/file safety checks, custom-scheme confirmation,
OSC 8 restrictions, view lifetime and the checked legacy callback stay intact.

Shade's provider reads kernel process cwd instead of its OSC/UI context cache.
It requires a live, identified foreground system shell and completely inspected
process tree; foreground children and unavailable metadata fail closed. Fully
inspected background process groups do not disable the fallback. Identity,
process groups and lifecycle are checked around the cwd read. OS inspection is
not atomic, so concurrent exec/job/chdir races cannot be eliminated completely.

The conservative fallback recognizes `/bin/sh`, `/bin/bash`, `/bin/zsh`,
`/bin/ksh`, `/bin/csh`, and `/bin/tcsh`. Without local OSC 7, custom shells,
multiplexers and active foreground commands have no trusted filesystem fallback.
This does not disable normal web links. Local OSC 7 still takes precedence,
including the upstream limitation that terminal output cannot itself prove locality.

The provider type explicitly includes `@Sendable` as well as `@MainActor`,
and the property is `final`: this new hook is not a subclass override point.
Explicit sendability alone did not fix Swift 6.2's inherited getter-symbol
mismatch. Making this accessor final removes its inherited vtable entries;
clean object inspection confirms the subclass has no callback accessor references.
Clean Xcode/default and native builds pass all 64 focused link tests.
These corrections do not change callback execution or safety behavior.

No parser bytes or fake OSC 7 are injected. Public view APIs cannot update
upstream's cwd without parser input; reconstructing a request would discard its
originating safety/lifecycle policy, and `openDefault` would lose Shade's reveal
callback. That is why a narrow fork hook is necessary.

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

- SwiftTerm final retained suite: 160 XCTest cases pass; 1,979 Swift Testing
  cases execute with only `controlSlashKeepsItsCodepointWithKittyKeyboardProtocol`
  failing under RussianWin (codepoint 46 instead of 47). The same failure is
  reproduced on untouched `v1.99.3` under the same layout.
- Earlier parallel runs exposed intermittent cursor-blink/headless timeout
  fixtures. Focused reruns pass; the final serial run has neither timeout.
- Added tint/underline coexistence, dynamic appearance, selection precedence,
  shaped-path fallback and actual CoreGraphics tint-on/tint-off pixel checks.
- An offscreen CoreGraphics preview was inspected. This is not a live app,
  editor or keyboard-event acceptance test.
- Shade debug: all 477 tests pass on the published fallback pin.
- Shade release: all 477 tests pass with optimizations.
- The real PTY integration exercises actual checked link activation before/after
  `cd`, same-name files, blocking after exit and restart; handlers capture all
  alerts/opens without launching another app. Error-aware process enumeration
  distinguishes failed libproc reads from genuinely empty trees.
- Focused fork link-policy/fallback coverage: 64 tests across four suites pass.
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

1. In a standard local shell without OSC 7, change directories and check a
   relative file link, including a same-name file in the app directory. It must
   reveal the shell file. Remote/unknown or ended sessions must not gain an
   application-directory fallback. Then test local/remote OSC 7 behavior.
2. Hover links with Command held. Check custom underline/background tint,
   unchanged foreground, wrapped links, changing highlight color and selecting
   across the link. Test ordinary URLs and local-file reveal behavior. Expect
   upstream safety checks for custom schemes and unsafe local targets.
3. Exercise keyboard selection by character/word/line, emoji, wide glyphs and
   wrapped rows, including while scrolled into history. Check Cut and clipboard.
4. Check OSC 133 prompt navigation (`⌘⇧↑` / `⌘⇧↓`) and output copy (`⌘⇧O`),
   after resize and with long scrollback. Clear previous output with a partially
   entered or multiline command; input must remain intact.
5. Run nano, vim, less and htop. Check cursor, redraw, scrolling, alternate-screen
   return, colors and translucency at normal and reduced opacity.
6. Open/close tabs and background sessions, then quit/restart the candidate.

After review, publication/merge/release remain separate actions. If rejected,
quit the candidate and reopen the unchanged installed app. No settings migration
or installed-app replacement is part of this upgrade branch.
