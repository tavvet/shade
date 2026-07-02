# De-vendoring SwiftTerm: fork + rebase migration plan

_Status: planned (not started). Drafted 2026-07-02._

## Why

Shade currently vendors SwiftTerm as an **in-place edited checkout** under
`Vendor/SwiftTerm/`. Over the project's life this silently accumulated ~6 local
patches woven into upstream source files, most **without markers**. A naive
re-sync to a newer upstream would lose them, so staying current with upstream
(and picking up other developers' bug fixes) is painful and risky.

**Goal:** move the local patches onto a rebase-tracked fork so an upstream sync
becomes `git rebase upstream/main`, and de-vendor Shade to a normal SPM
dependency. Conflicts, when they happen, are resolved locally — git-native,
with real 3-way markers, not hand-edited patch files (patch files rot as
upstream drifts; rejected).

The CoreGraphics renderer fix that triggered this investigation is **already
merged upstream** (SwiftTerm#582, merge commit `d5ee56e`, 2026-07-01), so it
drops out of our local set.

## Inventory of local patches (complete, as of 2026-07-02)

Derived from `git log --stat 9822b33..HEAD -- Vendor/SwiftTerm/` plus the initial
vendor commit `9822b33`.

| Patch | File(s) | Shade commit(s) | Fate |
|---|---|---|---|
| CoreGraphics renderer fix (dirty-region clear + bottom-edge extend) | AppleTerminalView, Terminal | `eb29009`→`57954b2` (5 commits) | **DROP** — merged upstream (#582) |
| Keyboard text selection in the buffer | MacTerminalView (+122) | `7ed6f6e` | keep |
| Configurable link-highlight color + cell tint | AppleTerminalView, MacTerminalView | `9822b33` + `00b6f91` | keep |
| Wheel → xterm button 4/5 (mouse reporting) | MacTerminalView (+41) | `14c10bf` | keep |
| `⌘X` = copy on read-only buffers | MacTerminalView (+9) | `40cad82` | keep |
| OSC 133 accessors (`scrollInvariantCursorRow`, `scrollInvariantLinesTop`, `maxScrollbackRow`) | Terminal (+26) | `5a721f0` | keep |
| Metal warning-silence (`_ = vertices.withUnsafeBytes {…}`) | MetalTerminalRenderer (+2) | `95508e0` | keep (trivial) |
| Package.swift trim (drop benchmark dep / fuzzer / termcast / tests) | Package.swift | `1b68328` | **verify** — see step 3 |

Net: **5 feature patches + 1 trivial**, renderer dropped.

## Target architecture

- Fork branch **`tavvet/SwiftTerm@shade`** = `upstream/main` + the keeper patches
  as clean, **one-per-feature** commits (final form, not the messy split history).
- Shade `Package.swift`: replace `.package(path: "Vendor/SwiftTerm")` with
  `.package(url: "https://github.com/tavvet/SwiftTerm", revision: "<sha>")`.
- **Remove `Vendor/SwiftTerm/`** from the Shade repo.
- Future sync = `git rebase upstream/main` on `shade` → force-push → bump the
  revision pin in Shade's `Package.swift`. Pin by **revision (SHA)**, not branch,
  for reproducibility.

## Migration steps

1. Create `shade` from `upstream/main` on the fork (upstream already has the
   renderer fix, so nothing to port for it).
2. Re-express each keeper as a clean commit on `shade` (final form; drop the
   renderer saga). Watch for any keeper upstream has since added itself
   (conflict / duplicate — e.g. selection or wheel handling).
3. **Verify `package-benchmark`:** check whether depending on the fork makes SPM
   resolve/fetch `package-benchmark` (that's what the vendor trim removed). If it
   does, keep a lean `Package.swift` on the `shade` branch; if modern SPM prunes
   deps outside the used product's closure, the trim isn't needed.
4. Point Shade's `Package.swift` at the fork (pin revision); delete
   `Vendor/SwiftTerm/`; `swift package resolve`.
5. `swift build` + `make build`.
6. Full retest (below).
7. Docs: update the README "Dependencies" note (now depends on the fork, not a
   vendored copy), THIRDPARTY if the attribution shape changes, and mark this
   plan done.

## Retest checklist (every feature that lives in a keeper patch)

- [ ] Keyboard text selection in the buffer
- [ ] `⌘X` copies on a **read-only** buffer (no backspaces sent)
- [ ] Wheel → xterm button 4/5 in mouse-reporting apps (`mc`, `htop`, `less -R`)
- [ ] OSC 133 prompt-mark nav (`⌘⇧↑` / `⌘⇧↓` / `⌘⇧O`) **and** no transparent-panel
      bug when scrolling to a mark near the cursor (`maxScrollbackRow` guard)
- [ ] Configurable link-highlight color + cell tint on `⌘`-hover
- [ ] Rendering clean in nano / vim / less / htop, translucency intact (renderer
      fix now comes from upstream — regression check)
- [ ] Build resolves without `package-benchmark` (or Package intentionally lean)

## Upstreaming philosophy (for the keepers — do NOT rush PRs)

Each keeper is a **feature / API addition**, not a bug — so no surprise PRs to
Miguel's repo. For each, evaluate: does it fit SwiftTerm's philosophy, or is it
Shade-specific? If generally useful → open an **issue first** to gauge the
maintainer, then maybe a PR. Bugs (like the renderer fix) → PR directly. Every
patch upstreamed = one fewer commit on the `shade` branch (drop it on the next
rebase). Don't spam PRs.

## References

- Merged renderer fix: [SwiftTerm#582](https://github.com/migueldeicaza/SwiftTerm/pull/582), merge commit `d5ee56e` (2026-07-01).
- Fork: https://github.com/tavvet/SwiftTerm
- Vendor base commit: `9822b33` (initial "Vendor SwiftTerm fork").
