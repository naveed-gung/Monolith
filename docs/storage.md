# Downloaded music — where it lives & what survives

Honest answer to "do my downloads survive an update / an uninstall?"

## Where files live today

`DownloadStore` keeps audio under a `Monolith/Music` folder:

- **Android:** `getExternalStorageDirectory()` →
  `…/Android/data/dev.naveed_gung.monolith/files/Monolith/Music`
- **iOS (and Android fallback):** `getApplicationDocumentsDirectory()/Monolith/Music`
  (visible in Files → On My iPhone → Monolith)

A `manifest.json` at the `Monolith` root records the library; on load, entries
whose backing file is gone are pruned, and any audio file found on disk that
isn't in the manifest is re-added (`loadTracksMergingDisk`).

## Update (install a new build over the old) — ✅ keeps everything

On **both platforms**, updating the app does **not** wipe app data — the
container persists. The new build reads the existing manifest, keeps every
present track, and new downloads prepend (newest-first). This is covered by
`test/download_store_survival_test.dart` (D1) and the ordering is deliberate in
`_rebuildTracks` (Task D1).

## Delete / uninstall — the honest split

### Android — re-discovery is implemented; true survival needs MediaStore (flagged)

What's **done & verified** (Dart, unit-tested): on launch the app scans the
Music folder and rebuilds the library from whatever audio files are present —
so if the files survive, the library repopulates from disk after a reinstall
without needing the manifest (`loadTracksMergingDisk`, D2 tests).

What's **NOT done** (flagged, needs native + a device): for files to actually
**survive uninstall**, downloads must be written to **OS-public storage**, not
the app-private external dir (which Android erases on uninstall). The correct
route is **MediaStore (`MediaStore.Audio`)** on API 29+, which requires a native
Kotlin `MethodChannel` and on-device verification. A path-only hack
(`/storage/emulated/0/Music/Monolith`) would only work on Android ≤9 and silently
fail under scoped storage on Android 10+, so shipping it as "survives uninstall"
would be a false claim on modern devices. **Deferred to a device session** — the
re-discovery half is ready to consume those surviving files the moment the
MediaStore write lands.

### iOS — not possible in-sandbox. No false claims.

iOS **always** erases the app container (Documents, including
"On My iPhone → Monolith") when the app is deleted. **There is no API to keep
files in the sandbox across an uninstall.** Options:

1. **iCloud Drive (ubiquity container):** the only "survives delete" path — write
   downloads to the app's iCloud container so they re-pull after reinstall (needs
   the user's iCloud + space; entitlement + config require a Mac to validate). Not
   implemented this round.
2. **Manual export:** the user can move files out of the Files app before
   deleting. Not automatic.
3. **Accept the platform rule:** on iOS, deleting the app removes downloads
   unless iCloud sync is enabled.

**Bottom line:** iOS update keeps everything; iOS delete removes downloads — by
Apple's sandbox rules, not a bug. Android update keeps everything, and reinstall
re-discovers any files that survive once downloads move to MediaStore public
storage (the remaining native piece).
