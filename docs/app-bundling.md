# App packaging

`make build` uses native SwiftPM and wraps its executable in a macOS app.
`make verify-bundle` checks the signature, release metadata, license notices
and runtime resource access. `make test-build` also checks failure propagation
and runs the resource smoke check with the developer's `.build` tree hidden.

## SwiftPM resources

The native SwiftPM-generated `Bundle.module` accessor searches beside the
main bundle, then falls back to an absolute path on the build machine. That
layout works for command-line executables, but a signed macOS app must store
resources in `Contents/Resources`. Putting bundles at the app root, including
symlinks, fails code signing with “unsealed contents present in the bundle root”.

For app builds, `scripts/prepare-resource-overlay.swift` creates a compiler
VFS overlay for the generated accessors of KeyboardShortcuts and SwiftTerm.
The replacements look in `Bundle.main.resourceURL` first, then beside the
executable for command-line use. They have no absolute build-machine fallback.
The overlay affects generated build sources only: dependency checkouts and
the SwiftTerm fork remain unchanged. A content hash in the overlay path makes
changed lookup logic invalidate cached compilation results.

Normal `swift test` and `swift build` still use SwiftPM's standard accessors.
The packaging invocation passes `-vfsoverlay` explicitly and copies both
resource bundles into `Contents/Resources` before signing.

SwiftPM's Xcode build backend generates an app-compatible accessor, but it
currently cannot build this dependency graph: the pinned SwiftTerm build-tool
plugin fails with a missing `SwiftTermBuildInfoPlugin` target. Keeping native
SwiftPM also preserves the existing host-architecture build behavior.

## Verification

The packaged executable supports a build-only `--verify-resource-bundles`
smoke check. It reads the bundled shader source and resolves a localized
KeyboardShortcuts key name through the library's real accessor. It exits
before creating the application, terminals, hotkeys, menus or preferences.

`make test-build` runs this check with `.build` inaccessible, then injects
copy, metadata and signing failures into the actual packaging recipe. It also
checks that missing resources and a removed signature are rejected. All
destructive fixtures are created in, and removed from, a temporary directory.
