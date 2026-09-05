# Monolith 1.1 — local handoff

The work is local. Nothing was committed, pushed, deployed, or published.
The owner uses TrollStore and prioritizes iOS. Existing uncommitted rebuild work
and vendored-package changes were preserved.

## Changes

| Before | After |
| --- | --- |
| Live Music import used a library scan; new native picker was disconnected | Settings and first-launch prompt call the native Music picker and report copied/skipped songs |
| Swift copied ipod-library URLs as filesystem paths | Accessible library assets export through AVFoundation; protected items remain unavailable |
| No explicit native Music permission handling | Permission request and denied-access error; cloud/protected items hidden in picker |
| Music import omitted cover art | Available Music artwork saved as a JPEG beside the copied audio |
| Files picker lacked explicit Apple type identifiers | Public audio/MPEG-4 identifiers provided for iOS selection |
| Storage exports only opened sharing | Native Save to Files on iOS and SAF destination picker on Android |
| Startup dialog used context above navigator | Navigator context and mounted checks; import error handled |
| Absolute iOS container paths could become stale | App-owned audio/artwork paths recover under the current container, preserving track metadata |
| Reads pruned missing manifest entries; writes could overlap | Reads retain on-disk metadata; serialized temporary-file replacement for library saves |
| Downloads tab opened first; small listening card | Library-first startup, larger artwork and real play/pause action; correct singular track count |
| Atmospheric gradients and live backdrop blur | Quiet canvas and flat panels/navigation; full player is opaque |
| Small compact playback controls | 48px targets and tappable player close handle; primary button minimums increased |
| Unbounded full-size artwork decoding and larger default image cache | Thumbnail-sized decoding; 96-entry / 32 MB decoded-image cache cap; stable timer numerals |
| Visualizer could animate while backgrounded | Lifecycle/reduced-effects gates; reduced effects enabled by default; position updates every 250–500 ms |
| Thumbnail network request could stall | Existing automatic download-artwork pipeline has a 15-second request timeout |
| Update button only opened GitHub | Stable platform asset selection; Wi-Fi automatic download while app is active; progress, timeout, size/header checks, bounded buffering and cached-file reuse |
| No installer handoff | TrollStore URL install plus local IPA sharing on iOS; restricted APK FileProvider and system installer on Android |
| Update UI version hardcoded at 1.0.4 | Local version 1.1.0+6; displayed update version aligned |
| Rebuild download manager raced stream completion/disposal | Serialized event handling and persistence, initialization synchronization, guarded notifications and immediate pause/cancel state updates |
| Playback-statistics writes raced each other and teardown | Serialized store writes and awaited repository shutdown; realistic test fixtures |

## Validation

- Full suite: 44 tests passed. Log: `build/regression.log`.
- Flutter analysis and Android debug build checked; logs in `build/analysis.log`
  and `build/android-build.log`.
- Pixel_10a: update install succeeded, test song discovered, foreground and
  background media session reported PLAYING without playback error.
- iOS Swift build and native Music/Files/TrollStore flows have NOT been run.
  Windows cannot build an IPA; macOS and the owner's iPhone are required.
- Reduced rendering and bounded image cache are code changes, not a measured
  claim that iPhone temperature or total process memory meets a specific number.

## iPhone acceptance checks

1. Build the local sources on macOS using the existing unsigned-IPA workflow
   commands, without publishing. Install over the same app with TrollStore.
2. Confirm the existing library and play history remain. Do not uninstall first.
3. Settings → Import from Music: grant permission, import an unprotected local
   song, check its artwork and offline playback. Also test cancel/denied access.
4. Storage → Save to Files: choose iCloud Drive or a local folder, then open the
   exported audio. Test cancellation separately.
5. Enable URL Scheme in TrollStore. Future published releases with a newer
   version and `monolith.ipa` asset can be handed to TrollStore. The direct
   TrollStore button uses the release URL; the cached IPA uses the share sheet.

## Desktop decision

Windows/Linux are deferred as requested. The installed playback and device-library
packages do not supply those platform implementations. No full-feature desktop
release below 150 MB RAM has been demonstrated. Android debug measured roughly
242 MiB PSS, which must not be treated as a desktop release-memory prediction.

## Remaining limits

No new GitHub release exists from this work. Auto-download is app-active work,
not an iOS background transfer service. Protected Apple Music subscription audio
cannot be copied into ordinary local files. The current iOS deployment target
remains 16.4. The older phased rebuild remains incomplete alongside the live app.
