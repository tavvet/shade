# Configuration storage

## Backends

Local storage is unchanged: `PreferencesStore` reads/writes scalar defaults,
and `SSHProfileStore` owns the original Application Support JSON. No automatic
migration runs. `ConfigurationStore.shared` selects this backend or a portable
folder. Its location is stored under the device-local `configurationDirectory`
defaults key, outside both portable documents.

The portable folder contains two versioned JSON documents:

- `settings.json`: `SettingsFileDocument` with version 4 and a typed `Preferences`
  snapshot. All fields are required; unknown enums and invalid ranges reject
  the document rather than silently normalizing someone else's file. Valid
  colors written as `#rrggbb` are read as uppercase `RRGGBB`, matching local
  defaults; the file itself is not rewritten.
  Schema changes must version the document or provide an explicit migration;
  do not add required fields while leaving the version unchanged.
  Older documents load through explicit migrations that add only the fields
  their version lacked, at their defaults: version 1 gains `tabMinimumWidth`
  (120 pt), versions 1 and 2 gain `backgroundHex` (`0D0D0D`) and
  `foregroundHex` (`EBEBEB`), and versions 1–3 gain `quitConfirmation`
  (`pinnedTabs`). All other
  fields remain required. Loading does not rewrite the file. The next settings
  save writes version 4, including the width (80–240 pt), colors (`RRGGBB`)
  and quit confirmation (`never`, `pinnedTabs` or `pinnedOrBusyTabs`).
  Shade releases before version 4 reject such a file, so every Mac sharing the
  folder needs a current build.
- `connections.json`: the existing `SSHProfileStore` version-1 envelope. UUIDs
  and array order retain identity and quick-slot order. It contains connection
  metadata and identity-file paths, never passwords or private-key contents.

Runtime consumers never look up a global store. `AppDelegate` passes
`ConfigurationStore.shared` to each controller as `PreferencesProviding`
(read-only) or `PreferencesStoring` (read and write); controllers hand value
snapshots to the sessions they create. Explicit `PreferencesStore(userDefaults:)`
remains the local-only implementation for tests and migration-independent
defaults access. `PreferencesStoring` lets SettingsModel handle persistence
failures. The
`ConfigurationSSHProfileStore` adapter connects the SSH controller to the same
selector without making either document's codec depend on application lifecycle.

## Switching

Inspection never writes. Empty means both filenames are absent, not merely
unreadable. Copying creates private files without replacing existing targets.
Only after both files load successfully is the local location pointer changed.
If a copy fails partway through, the active location stays unchanged; any new
destination files remain for recovery. No recursive cleanup touches a selected
folder. A partial existing pair must be repaired or replaced by the user.

Using an existing folder validates both documents and changes only the pointer.
Returning to local storage restores the preserved local configuration, not a
copy of the current portable settings. Every switch is explicitly confirmed;
neither source is removed or implicitly overwritten.

## External edits and failures

`ConfigurationStore` is the only sender of `ShadePreferencesChanged`, always with
itself as the notification object. Every save, reload and storage switch
publishes through one change check against the last announced snapshot, so
the notification means the values returned by `load()` differ from those
observers last applied; a rejected or failed save, or a reload that finds the
same values, posts nothing. `PreferencesChangeAnnouncer` posts after the
storage transaction returns: the first change at once, later ones in a burst
at most every 120 ms, with a final post for the latest values. Storage switches
and Reload Files also post `ShadeConfigurationChanged`, which reloads the
connection library. Observers subscribe to their own store's announcements.
Active terminal sessions are preserved.
The app reloads at panel/Settings/picker presentation and before a quick-slot
connection; Storage also offers an explicit Reload Files action. There is no
continuous file watcher or cloud completion indicator.
Runtime preference reads return the last valid snapshot without touching files.
All document I/O (including provider metadata and coordination) runs off the
main actor. F12 shows the cached configuration immediately; a successful refresh
updates running views afterwards. Until the first portable read completes,
preserved local preferences provide the fallback, including for a terminal
opened during startup. Shell-only changes still require a new terminal session.
Storage transactions are serialized through `ConfigurationTaskQueue`, including
publication and location changes. Pending writes finish before normal app quit;
an unrelated background read does not delay quitting.
Changing the selected storage invalidates in-flight SSH loads immediately.
Their results are discarded and the controller reads the new backend before
allowing edits. Picker connections (quick slots, Enter, and clicks) wait for a
refresh; dismissing the picker cancels its pending connection, and a later
request replaces an earlier one. Cached connections remain usable after a
failed refresh, but are not launched while the refresh is still pending.
The Settings page disables its Connect actions for that pending interval.
Both files must be downloaded locally. Evicted iCloud files report an error
before coordinating a read; Shade does not initiate a download from the UI.

Portable writes coordinate with file providers through `NSFileCoordinator`.
Inside the coordinated write, the latest document is compared with the editing
controller's base snapshot. A changed base rejects the write. Importantly, a
background preferences read cannot replace the SSH controller's editing base.
Local SSH saves also compare the current file against the editing base before
replacement, so an old portable snapshot cannot overwrite the preserved library
after returning to local storage.
Local preference saves likewise compare their base with the current defaults
inside the serialized write, without suspending between comparison and save.
An unrelated Settings edit therefore cannot silently undo a queued keyboard
font zoom. A conflict rejects the stale edit; Settings shows the error and
reloads the current values so the user can retry. This is an in-app stale-write
check, not a cross-process transaction for UserDefaults.
Keyboard zoom uses `updateFontSize`, which reads the stored size, applies the
zoom step, clamps it to 8–32 pt and saves inside one serialized write, so it
always steps from the size currently in UserDefaults or `settings.json` and
keeps other fields that another writer changed. A zoom that does not change
the size writes nothing. In a portable folder, preference saves and zoom
decode `connections.json` and then read, change and replace `settings.json`
inside a single coordinated write; an invalid or evicted connections file
blocks the write, as for any other change to an incomplete pair.
The SSH editor and deletion confirmation additionally retain the original
profile: reloading the controller does not authorize overwriting that profile's
newer values with an older draft. Cancel and reopen a stale editor to retry.
Each write uses a private sibling file and an atomic replacement. Documents
are limited to 5 MB each and must be regular, non-symlink files. The size limit
is checked before replacing a file; copying preflights both encoded documents
before creating either file. Settings edits arriving during a save are coalesced
and persisted in order; the SSH editor stays open until its save succeeds.

This is not a distributed merge algorithm: cloud services may deliver offline
edits later, and the two files sync independently. Use one writer at a time;
provider conflict copies require manual resolution. A missing/invalid custom
file is never treated as an empty library or permission to recreate defaults.
The last valid preferences remain in memory; on a fresh launch, the preserved
local preferences are the read-only fallback until custom storage recovers.

Tests use isolated defaults suites and temporary folders. Cover copy/use/return,
failed or incomplete selection, missing active files, startup without the
folder, external edits to each document, font zoom, profile ordering, location
changes during SSH reload, cancellation of picker requests, and file permissions.
Manual QA must also cover the native directory picker and iCloud
Drive availability on actual Macs.
