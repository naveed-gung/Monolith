# Monolith audit — 9 September 2026

Audited the current working copy, version 1.4.3+12. This is a findings report, not a claim that every device, file format, or failure mode has been tested. No newly discovered production fixes were applied during this audit. Earlier requested fixes and existing uncommitted work were preserved.

## Results

| Check | Result |
| --- | --- |
| Existing automated tests, rerun with coverage | 71 passed |
| Analysis of lib and test | No issues |
| Fresh Android debug APK | Built and installed successfully |
| UI matrix: 7 screens × 5 configurations | 32 without reported layout exceptions; 3 failed |
| Additional controller probes | 5 failed |
| Additional storage probes | 6 failed |
| Android Back probe | Failed; also reproduced on emulator |

The 47 targeted checks produced 15 failures, grouped below rather than counted as 15 independent bugs. Visual/source inspection adds the missing tablet navigation issue: **12 principal findings**. A passing layout check means no captured layout exception, not that the screen is fully usable.

UI configurations: 375×812 phone, 320×568 small phone, 375×812 with 200% text, 812×375 landscape, and 1024×768 tablet. Screens: Library, Downloads, Songs, Search, Player, Settings, Storage. Screenshots use real Roboto metrics and bundled icon fonts; they are Flutter-rendered fixtures, not native iPhone screenshots. The storage path's monospace fallback is not representative of native text rendering.

## Prioritized findings

P1 = fix before wider distribution: user data/recovery or a broken core flow. P2 = normal-priority functional/accessibility repair.

| # | Priority | Finding and reproduction | Evidence / repair direction |
| --- | --- | --- | --- |
| 1 | P1 | Playlists disappear after controller restart. Create “Road trip,” add a song, restart with the same preferences and tracks: the playlist is gone. Favorites use the same memory-only map. | Controller probe fails on the missing playlist; Favorites loss is source-confirmed, not reached by that assertion. [Playlist state](<C:/Users/naveed/Documents/Work/Personal/Mobile/Flutter projects/Monolith/lib/src/app/state/app_controller.dart:171>). Persist names/membership and restore them using stable track IDs. |
| 2 | P1 | A damaged manifest prevents recovery of audio that still exists on disk. Truncated JSON throws before the disk scan; library refresh reports an error and may remain empty on cold start. Files are not deleted. | Storage probe raises FormatException. [Manifest decoding](<C:/Users/naveed/Documents/Work/Personal/Mobile/Flutter projects/Monolith/lib/src/core/services/download_store.dart:115>) and [Recovery entry point](<C:/Users/naveed/Documents/Work/Personal/Mobile/Flutter projects/Monolith/lib/src/core/services/download_store.dart:186>). Quarantine malformed metadata, recover files, and test interrupted writes. |
| 3 | P1 | Android Back leaves the app while the full player is open instead of dismissing the player. | Widget probe fails; the freshly built emulator app switched to NexusLauncher after Back. [Shell](<C:/Users/naveed/Documents/Work/Personal/Mobile/Flutter projects/Monolith/lib/src/features/shell/presentation/music_shell.dart:126>) has no player-aware back handling. [Device screenshot](<C:/Users/naveed/Documents/Work/Personal/Mobile/Flutter projects/Monolith/artifacts/audit/device-back.png>). |
| 4 | P2 | “Wi-Fi only” is bypassed by Retry. Start a failed download on Wi-Fi, switch connectivity to mobile, retry: the downloader is invoked again. This can consume cellular data. | Mock-connectivity controller probe. [Retry](<C:/Users/naveed/Documents/Work/Personal/Mobile/Flutter projects/Monolith/lib/src/app/state/app_controller.dart:1182>) bypasses the initial-start check; Resume follows the same unchecked route by inspection. Enforce policy at the shared transfer entry point. |
| 5 | P2 | Shuffle does not shuffle, and Previous advances. With three tracks, Next then Previous lands on the third rather than the starting track. | Controller probe. [Queue movement](<C:/Users/naveed/Documents/Work/Personal/Mobile/Flutter projects/Monolith/lib/src/app/state/app_controller.dart:1387>) uses direction.abs(); queue order remains identity. Maintain a shuffled order and playback history. |
| 6 | P2 | Re-importing the same native Music item can create duplicate library entries and copies. Two export results with the same metadata but different UUID paths produce two songs. | Controller probe uses synthetic native payloads; not a live iOS export. [Path-only deduplication](<C:/Users/naveed/Documents/Work/Personal/Mobile/Flutter projects/Monolith/lib/src/app/state/app_controller.dart:881>). Carry stable native identity through export; do not deduplicate unrelated songs solely by title. |
| 7 | P2 | Tablet layout removes all visible main-tab navigation above 880 logical pixels, without a replacement rail/menu. | All tablet captures show navigation absent; [1024×768 Library](<C:/Users/naveed/Documents/Work/Personal/Mobile/Flutter projects/Monolith/artifacts/audit/tablet-library.png>), [Width condition](<C:/Users/naveed/Documents/Work/Personal/Mobile/Flutter projects/Monolith/lib/src/features/shell/presentation/music_shell.dart:277>). Swiping does not replace discoverable, accessible navigation. |
| 8 | P2 | Small-phone Settings overflows by 29 pixels. The developer name and “System” label also wrap into awkward fragments. | [320×568 Settings](<C:/Users/naveed/Documents/Work/Personal/Mobile/Flutter projects/Monolith/artifacts/audit/small-settings.png>); [Settings layout](<C:/Users/naveed/Documents/Work/Personal/Mobile/Flutter projects/Monolith/lib/src/features/settings/presentation/settings_page.dart:212>). Use wrapping/reflow for accent choices and a compact profile arrangement. |
| 9 | P2 | At 200% text, the bottom navigation overflows vertically by 13 pixels; Downloads wraps and clips. | [Large-text Library](<C:/Users/naveed/Documents/Work/Personal/Mobile/Flutter projects/Monolith/artifacts/audit/large-text-library.png>); [Navigation layout](<C:/Users/naveed/Documents/Work/Personal/Mobile/Flutter projects/Monolith/lib/src/features/shell/presentation/music_shell.dart:398>). Give labels sufficient space and test scaled text across tabs. |
| 10 | P2 | At 200% text, Storage's “Copy path” and “Open in Files” actions overflow their available widths by 2.6 and 35 pixels. | [Large-text Storage](<C:/Users/naveed/Documents/Work/Personal/Mobile/Flutter projects/Monolith/artifacts/audit/large-text-storage.png>); [Storage actions](<C:/Users/naveed/Documents/Work/Personal/Mobile/Flutter projects/Monolith/lib/src/features/storage/presentation/storage_page.dart:319>). Stack or wrap the actions at constrained widths. |
| 11 | P2 | Disk recovery skips five extensions offered by the file importer: aiff, alac, amr, oga, weba. When metadata is missing, these surviving files are not restored. | Five storage probes. [Recovery whitelist](<C:/Users/naveed/Documents/Work/Personal/Mobile/Flutter projects/Monolith/lib/src/core/services/download_store.dart:37>) versus [Importer whitelist](<C:/Users/naveed/Documents/Work/Personal/Mobile/Flutter projects/Monolith/lib/src/core/services/manual_audio_import_service.dart:22>). Share one supported-format policy. Fixtures test extension routing, not codec decoding. |
| 12 | P2 | Up Next lists earlier songs at the final track even with repeat off. It contradicts the queue's end state. | Controller probe. [Up Next rotation](<C:/Users/naveed/Documents/Work/Personal/Mobile/Flutter projects/Monolith/lib/src/app/state/app_controller.dart:387>) always wraps. Build preview from the same repeat/shuffle rules used by actual playback. |

## Other blind spots and follow-up risks

These are separate from the 12 principal findings; native failure paths below were not reproduced on a device.

- **Incoming shared audio:** Android advertises audio VIEW/SEND handling, but [MainActivity](<C:/Users/naveed/Documents/Work/Personal/Mobile/Flutter projects/Monolith/android/app/src/main/kotlin/dev/naveed_gung/monolith/MainActivity.kt:15>) has no incoming-audio forwarding path found in this review. Exercise “Open with Monolith” and sharing from Files/messaging apps, both cold and warm starts.
- **Export can report false success:** [Android export handling](<C:/Users/naveed/Documents/Work/Personal/Mobile/Flutter projects/Monolith/android/app/src/main/kotlin/dev/naveed_gung/monolith/MediaImportHandler.kt:239>) swallows copy failures and can return canceled=false with savedCount=0; [Storage success message](<C:/Users/naveed/Documents/Work/Personal/Mobile/Flutter projects/Monolith/lib/src/features/storage/presentation/storage_page.dart:43>) ignores savedCount. Inject a failing document provider or full destination and verify the user gets an actionable failure.
- **Collection queue context:** navigation generates indices for the entire library. Verify album/playlist playback stays inside the selected collection instead of escaping into unrelated tracks.
- **Landscape usability:** [Landscape player](<C:/Users/naveed/Documents/Work/Personal/Mobile/Flutter projects/Monolith/artifacts/audit/landscape-player.png>) initially shows almost only artwork. Controls are below the fold in a scrollable list, not missing; a compact landscape arrangement would make playback easier.
- **Tested architecture versus shipped architecture:** the entry point uses lib/src. A well-tested repository under lib/data does not automatically prove the live controller has that feature. Backup/restore and playlist durability especially need end-to-end checks through the shipped UI.
- **Build upkeep:** the debug build warned about future Flutter support for the current Android Gradle plugin. The Android release configuration uses debug signing; release signing/distribution needs a deliberate check before publishing. No dependency or signing changes made.

## Coverage and remaining device work

The baseline run measured 3,609 covered lines out of 6,733 reported Dart lines across 43 files: **53.6%**. This is line coverage for reported files, not whole-product feature coverage.

| Area | Covered / reported lines |
| --- | --- |
| Live controller | 605 / 1,127 |
| Download store | 132 / 198 |
| Shell | 260 / 353 |
| Settings | 323 / 465 |
| Storage screen | 1 / 219 |
| Separate playback repository | 123 / 131 |

Still required before calling this release-ready:

- Real iPhone import/export: foreground, screen lock, background, calls/audio interruption, protected or unavailable Music items, batch cancellation, and partial failures. The supplied AVFoundationErrorDomain -11847 screenshot reports an interrupted operation; it does not establish which event interrupted it. Windows testing cannot validate the Swift retry or reproduce that native error.
- Physical Android/iOS playback: audible output, Bluetooth/headphone changes, lock-screen controls, long background playback, and interruption recovery. Emulator checks do not prove sound quality or native lifecycle reliability.
- Process-death/relaunch during downloads and imports; low storage, revoked permissions, unavailable/moved files, and backup/restore.
- Real provider downloads, network loss/reconnection, invalid links, rate limits, and Wi-Fi-to-cellular transitions during an active transfer.
- Large libraries, long/non-Latin metadata, sustained scrolling, memory/performance, dark theme matrix, TalkBack/VoiceOver, and reduced-motion behavior. This audit did not complete these combinations.

## Earlier reported issues

- Search keyboard dismissal and removal of the player navbar: seen working on the freshly built Android app after selecting the test song from Search. [Device player screenshot](<C:/Users/naveed/Documents/Work/Personal/Mobile/Flutter projects/Monolith/artifacts/audit/device-player.png>).
- Repeat default off and remembered off/all/one: existing controller regression passes.
- Activity announcement not replaying on screen changes and popup spacing: existing regressions pass.
- iOS interrupted import: earlier Swift changes remain present, but have not been compiled/run on iOS here. No claim that the original failure is fixed on the phone.

## Reproduction and evidence

Run from this project directory after an Android debug build:

```powershell
flutter test --no-pub
flutter analyze --no-pub lib test
flutter test --no-pub artifacts/audit/controller_probe_test.dart
flutter test --no-pub artifacts/audit/storage_probe_test.dart
flutter test --no-pub artifacts/audit/ui_probe_test.dart
```

The audit probes intentionally assert the desired behavior and currently fail. They live outside test/ so the baseline suite remains separately identifiable. The UI harness currently references this machine's Flutter font cache and generated Android assets; adjust those paths on another machine.

Evidence: [Baseline log](<C:/Users/naveed/Documents/Work/Personal/Mobile/Flutter projects/Monolith/artifacts/audit/baseline-tests.txt>), [controller failures](<C:/Users/naveed/Documents/Work/Personal/Mobile/Flutter projects/Monolith/artifacts/audit/controller-results.txt>), [storage failures](<C:/Users/naveed/Documents/Work/Personal/Mobile/Flutter projects/Monolith/artifacts/audit/storage-results.txt>), [UI results](<C:/Users/naveed/Documents/Work/Personal/Mobile/Flutter projects/Monolith/artifacts/audit/ui-results.json>), [UI log](<C:/Users/naveed/Documents/Work/Personal/Mobile/Flutter projects/Monolith/artifacts/audit/ui-test-log.txt>), [Back failure](<C:/Users/naveed/Documents/Work/Personal/Mobile/Flutter projects/Monolith/artifacts/audit/back-button-results.txt>), [coverage](<C:/Users/naveed/Documents/Work/Personal/Mobile/Flutter projects/Monolith/artifacts/audit/lcov.info>).

A dedicated read-only Pixel_10a emulator session was used and then closed. The user's saved emulator data was not wiped. A transient Android System UI startup ANR was excluded from Monolith findings. No commits, pushes, deployments, or production-data deletions were performed.

Suggested repair order: playlist durability and damaged-metadata recovery; Android Back; Wi-Fi enforcement; queue/shuffle correctness; import identity; responsive/accessibility fixes. Keep each failing probe as a regression when its corresponding repair lands.

