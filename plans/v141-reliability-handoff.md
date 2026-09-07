# v1.4.2 reliability patch — 2026-09-07

Developed against v1.4.1+10 with the user's current coral accent retained. Initially kept local at the user's request; the user subsequently authorized committing and publishing to GitHub. Release version: v1.4.2+11.

## Behavior changes

| Before | After |
| --- | --- |
| The expanded activity pill took width from the title | Separate activity row below Library/Downloads headers; title width is stable |
| Only the first song job was exposed; tiny stop target | Live dropdown lists each song/import/update with a separate 48px stop control |
| Header carrier had fixed dark colors in light mode | Activity surfaces follow the selected theme and accent |
| Zero-byte sources could enter the extractor's internal retry loop | Owned transport bounds requests, checks ranges/byte counts, and tries at most two mobile manifests |
| Highest bitrate could select a surround audio variant | Prefer standard AAC when available; retain MP4/AAC requirement on iOS |
| 0% transfer looked like ongoing downloading | Connecting label and indeterminate progress until bytes arrive; explicit errors for unavailable sources |
| Notification/storage channel creation replaced import callbacks | Only the active import registers a progress handler |
| Native import released its busy lock before export | Lock retained until batch completion/cancellation; completed copies are kept |
| Exported M4A used a .tmp extension | Real extension inside a staging directory outside Music; both copy/export paths validated before moving |
| Native export/read operations could wait indefinitely | Bounded export and metadata operations; cancellation finishes once, ignoring late callbacks |
| All failures described as protected/unavailable | Actual per-song reasons retained in the controller and activity results |
| Update install could fall back to a remote URL | Open downloaded IPA shares the existing local file to TrollStore/Files |
| Downloaded IPA disappeared from UI after restart | Persist release metadata and restore the verified cached package |
| Installer launch could claim installation success | No success/restart claim without actual installation evidence |
| Broad cache cleanup risked deleting shared/ready packages | Clean only updater-owned stale files; preserve ready IPA and active transfer |

## Validation

- 67 unit/widget tests pass; analyzer clean; Android debug build passes.
- Regression tests cover empty/rejected/truncated/stalled/cancelled HTTP responses, ranges, import cancellation ownership, bridge callback survival, narrow-header layout, concurrent stop controls, local IPA sharing and offline cache restoration.
- Short public source `jNQXAC9IVRw`: complete 309,288-byte AAC transport verified locally.
- Longer public source `aqz-KE-bpKQ`: progressed on the emulator, then source HTTP 403. Standard AAC and an alternative extractor client were also checked; source rejection remains an external limitation. No claim that all YouTube sources are repaired.
- The user clarified that every song they choose fails to download on the iPhone. The short desktop success does not establish that the iOS failure is resolved; the updated transport still needs verification on that phone.
- Six replacement README screenshots alternate Library light, Songs dark, Player light, Downloads dark, Search light, Settings dark.

## iPhone verification remains

This Windows machine cannot compile the Swift changes or exercise Music/TrollStore on the target phone. Verify Import All, picker import, cancellation, the formerly failing songs, and opening a locally downloaded IPA on that phone. Keep originals until the copied audio plays after restart in airplane mode.

## Source behavior reference

The dependency has an internal `_getStream` branch that refreshes manifests on fatal HTTP failures. The upstream source-rejection report is https://github.com/Hexer10/youtube_explode_dart/issues/386. The app now owns transfer deadlines and terminal failures instead of waiting on that loop.
