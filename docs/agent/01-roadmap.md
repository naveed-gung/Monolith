<!-- AGENT NOTE: Before ending your session, update the Status table below if you
touched anything related, bump last-verified, and append to SESSIONS.md.
Rules: docs/agent/PROTOCOL.md -->
---
doc: 01-roadmap
last-verified: 2026-11-10
verified-by: devin
---

# Monolith — roadmap & open work

Seeded 2026-09-19 while reviewing the download-history / playback-order batch. Every
task below came from reading the code or running the tooling — no filler.

## Status

| ID | Title | Priority | Effort | Status | Last touched |
|----|-------|----------|--------|--------|--------------|
| TASK-13 | Monolith app Wi-Fi sharing (send + receive, desktop-compatible) | P1 | L | DONE | 2026-11-10 |
| TASK-14 | Premium player open/close shared-element transition | P1 | M | DONE | 2026-11-10 |
| TASK-15 | Bluetooth RFCOMM sharing (Android-only, after LAN) | P2 | L | TODO | 2026-11-10 |
| TASK-07 | Android CI signs every build with a throwaway key | P1 | M | TODO | 2026-09-20 |
| TASK-10 | Edit Up Next and keep system controls in sync | P2 | L | TODO | 2026-09-29 |
| TASK-11 | Stop playback with a sleep timer | P2 | M | TODO | 2026-09-29 |
| TASK-01 | Exclude probe directories from `flutter analyze` | P2 | S | TODO | 2026-09-19 |
| TASK-02 | Cap the persisted download history | P2 | S | TODO | 2026-09-19 |
| TASK-08 | `v1.4.4` release assets no longer match the `v1.4.4` tag | P2 | S | BLOCKED | 2026-09-20 |
| TASK-03 | Recover source links for pre-`sourceUrl` downloads | P3 | M | TODO | 2026-09-19 |
| TASK-09 | Version string is duplicated across four files | P3 | S | TODO | 2026-09-20 |
| TASK-12 | Save and resume listening sessions (proposal) | P3 | L | TODO | 2026-09-29 |
| TASK-04 | `android.yml` CI | P3 | M | DONE | 2026-09-20 |
| TASK-06 | Publish releases only from a `v*` tag | P1 | S | DONE | 2026-09-20 |
| TASK-05 | Custom shuffle/repeat on the iOS Lock Screen | P3 | M | DROPPED | 2026-09-19 |

## Tasks

### TASK-13 Monolith app Wi-Fi sharing (send + receive, desktop-compatible)
Priority: P1 · Effort: L · Depends: — · Files: `lib/src/core/services/nearby/*`, `lib/src/features/nearby/presentation/*`, `android/app/src/main/AndroidManifest.xml`, `android/app/src/main/kotlin/.../MainActivity.kt`, `ios/Runner/Info.plist`

**Why**: Desktop 0.6.0 ships UDP discovery (port 45881) + a raw framed protocol over TLS 1.3 (`docs/nearby-music.md`, `src/lan.rs`, `src/nearby.rs`). Mobile implements the same wire v1: 4-byte BE length + bounded JSON (≤16,384), exact hello, validated offer, accept/decline, exact-size raw audio (≤100 MB), `saved` receipt only after import succeeds.

**Done 2026-11-10**:
- `nearby_wire.dart` — constants, exact hello equality, `NearbyOffer`/`nearbyValidName` port (traversal, reserved stems, ≤180-byte name, ≤480-byte title, wire extension set), local-IPv4 filter, fingerprint validation.
- `nearby_certificate.dart` — ephemeral P-256 self-signed cert in pure Dart (no new dep): DER encoder + SEC1/PKCS8 PEM; BoringSSL accepts it (TLS loopback test proves the handshake).
- `nearby_channel.dart` — framing over `Socket`/`SecureSocket`: 75 s idle per wait, 15 min absolute, 60 s consent, destroy-on-cancel.
- `nearby_discovery.dart` — 2 s broadcast scan (nonce-checked `available` replies, ≤2048 B, ≤32 peers) + responder answering only while Receive is open.
- `nearby_session.dart` — `SecureSocket` client pinning the discovery fingerprint via `onBadCertificate` (no accept-all; TLS 1.3 floor via `minimumTlsProtocolVersion`); `NearbyReceiver` = ephemeral `SecureServerSocket` + responder, serial accept loop.
- `nearby_transfer.dart` — `nearbySend`/`nearbyReceive` state machines, `.part` staging, SHA-256 + magic-byte audio probe, publish via existing `DownloadStore.saveImportedAudio` (no-overwrite), `controller.refreshLibrary()` import before receipt.
- UI: Share sheet → "Monolith app" (peer picker, auto-rescan every 5 s, real progress, cancel) / "Receive" (5-min foreground session, per-song consent dialog with 60 s countdown, progress, close stops everything) / "Other apps" (old share_plus path). Wired into Songs + Library track menus.
- Platform: `ACCESS_WIFI_STATE` + `CHANGE_WIFI_MULTICAST_STATE` in the manifest; `monolith/nearby` MethodChannel holds a `WifiManager.MulticastLock` only while Share/Receive is open (MainActivity.kt); iOS `NSLocalNetworkUsageDescription` now mentions sharing.
- Bluetooth RFCOMM deferred → TASK-15 (per spec: only after LAN works).

**Verification**: `test/nearby_test.dart` — 17 tests: fixtures roundtrip, hello/offer validation incl. malformed/oversized/hash, spoof rejection, discovery loopback, real TLS 1.3 loopback send+receive (BoringSSL ↔ generated cert, pinned fingerprint), changed-cert rejection, decline/cancel/partial/hash/non-audio/import-failure leave no song. `flutter analyze` clean for lib/+test/.

**Risks/rollback**: real device↔desktop interop unverified (loopback only); iOS untested (no build on Windows). Revert = drop `lib/src/features/nearby/` + `lib/src/core/services/nearby/` and the two `_shareTrack` swaps.

### TASK-14 Premium player open/close shared-element transition
Priority: P1 · Effort: M · Depends: — · Files: `lib/src/features/shell/presentation/music_shell.dart`

**Done 2026-11-10**: player overlay converted from an in-Stack `AnimatedSwitcher` to a transparent `PageRouteBuilder` pushed/popped in lockstep with `controller.isPlayerOpen` (`_syncPlayerRoute`). Fade + scale(0.94→1) container-transform transition at `AppMotion.durSlow` with `emphasized`/`exit` curves; the existing `player-artwork-{id}` Hero now actually flies between mini player and full player (mini stays mounted while open so both endpoints exist). Drag-down keeps tracking the finger, velocity-settles, flings off-screen then pops; back/tap pops → reverse transition, no instant pop. `MediaQuery.disableAnimations` → zero durations. Overlay root is `Material` (route has no Scaffold ancestor — Slider needs it) wrapped in RepaintBoundary.

**Verification**: `responsive_ui_regression_test.dart` (incl. "Android back closes the full player") + `widget_test.dart` — 48 tests green.

### TASK-15 Bluetooth RFCOMM sharing (Android-only, after LAN)
Priority: P2 · Effort: L · Depends: TASK-13 · Files: `lib/src/core/services/nearby/`, `android/app/src/main/kotlin/.../`

**Why**: Spec allows Android-only RFCOMM (`listenUsingRfcommWithServiceRecord`/`createRfcommSocketToServiceRecord`, UUID `e8793c34-...`, secure RFCOMM only) but only if time remains after LAN works; omitted cleanly this session. Deferred, not dropped — the wire protocol layer (`nearby_channel`/`nearby_transfer`) is transport-agnostic and can sit on an RFCOMM socket via a Kotlin EventChannel/MethodChannel bridge.

**Acceptance criteria**: paired-device picker → send; receive session; secure RFCOMM only; runtime BLUETOOTH_CONNECT (SDK 31+); all socket/hash/import work off the UI thread.

### TASK-10 Edit Up Next and keep system controls in sync
Priority: P2 · Effort: L · Depends: — · Files: `lib/src/app/state/app_controller.dart`, player/queue UI, media controls

**Why**: The queue follows the order selected from a list, but the listener cannot insert a song next, rearrange upcoming songs, or remove one without starting over. The owner requested an editable Up Next queue, with lock-screen next/previous following the same order.

**Acceptance criteria**:
- [ ] A song can be added with Play Next, upcoming songs can be reordered by drag, and any upcoming song can be removed.
- [ ] The current song keeps playing while Up Next is edited; the resulting order is used for automatic advance and in-app next/previous.
- [ ] iOS and Android system media controls use the same resulting order when next/previous is available.
- [ ] Queue changes behave predictably with shuffle, repeat, sorted/filtered lists, and tracks removed from the library.

**Agent instructions**: Trace the existing queue order and media-session handoff before changing it. Keep one queue authority and test edits during playback, including system next/previous.
**Verification**: Focused queue tests plus manual background/lock-screen playback on iOS and Android.
**Risks/rollback**: A second queue representation could make the lock screen and app disagree; keep edits in the playback queue model. Revert the queue-editing UI and mutations if synchronization regresses.

### TASK-11 Stop playback with a sleep timer
Priority: P2 · Effort: M · Depends: — · Files: player UI, playback controller

**Why**: The owner requested 15-, 30-, and 60-minute stop options plus stop at the end of the current song.

**Acceptance criteria**:
- [ ] The listener can start a 15-, 30-, or 60-minute timer, or choose End of current song.
- [ ] The active timer is visible and can be canceled or changed.
- [ ] Playback stops once at the chosen boundary, including while the app is backgrounded or the phone is locked, without clearing the queue.
- [ ] If playback is already stopped or a track changes, the timer behavior remains clear and consistent.

**Agent instructions**: Use the existing playback lifecycle as the timer authority; avoid a UI-only timer that stops when the page is disposed. Test end-of-song with repeat enabled.
**Verification**: Timer/controller tests for expiration, cancellation, and end-of-song; manual background/lock-screen check on iOS and Android.
**Risks/rollback**: Background suspension and repeat handling can miss a stop boundary; keep the timer state observable and easy to cancel. Revert the timer feature if it affects normal advancement.

### TASK-12 Save and resume listening sessions (proposal)
Priority: P3 · Effort: L · Depends: TASK-10 · Files: playback controller, local storage, player UI

**Why**: A playlist remembers songs, but not where the listener was. A local listening session could preserve the exact queue, current song and timestamp so someone can switch contexts and later resume where they left off. This is a proposal for owner review, not approved implementation scope.

**Acceptance criteria**:
- [ ] A listener can name and save the current queue, current track, position, shuffle, and repeat state locally.
- [ ] Restoring a session resumes that state without deleting or changing existing playlists.
- [ ] Missing tracks are skipped with a clear explanation; the feature never silently replaces them with different audio.
- [ ] The owner confirms the interaction design and whether automatic session snapshots are wanted before implementation.

**Agent instructions**: Confirm the proposed scope with the owner first. Reuse the editable queue from TASK-10; keep all session data on device.
**Verification**: Restore tests across relaunch, queue edits, and missing tracks; manual iOS/Android playback check.
**Risks/rollback**: Persisted paths may point to removed audio; validate each track on restore and preserve the saved session for recovery.

### TASK-01 Exclude probe directories from `flutter analyze`
Priority: P2 · Effort: S · Depends: — · Files: `analysis_options.yaml`, `artifacts/audit/`, `build/mux_probe.dart`, `scripts/source_probe.dart`

**Why**: `flutter analyze` reports 17 issues, none of them in shipped code — 12 warnings
from `artifacts/audit/*_probe_test.dart` (unused imports, `invalid_use_of_visible_for_testing_member`,
unused declarations), 4 infos from `build/mux_probe.dart` (`avoid_print`,
`avoid_relative_lib_imports`) and 1 from `scripts/source_probe.dart`. Constant noise
trains everyone to ignore the output, so a real regression hides in it.

**Acceptance criteria**:
- [ ] `flutter analyze` prints `No issues found!`
- [ ] the exclusion is scoped — `lib/**` and `test/**` stay fully analyzed
- [ ] probes that are genuinely dead are deleted rather than merely hidden

**Agent instructions**:
1. Decide per directory: `artifacts/audit/` and `build/` are generated/throwaway → add to the existing `analyzer.exclude` block in `analysis_options.yaml` (it already excludes `third_party/**`); `scripts/source_probe.dart` is a kept tool → fix its relative `lib/` import instead of hiding it.
2. Confirm `build/` is not already covered — it is not, because the probe was written into the build output directory.
3. Re-run `flutter analyze`.

**Verification**: `flutter analyze` exits 0 with no issues; `flutter test` still passes.
**Risks/rollback**: over-broad excludes could mask real lints in shipped code — keep the globs directory-specific. Revert = drop the added glob lines.

### TASK-02 Cap the persisted download history
Priority: P2 · Effort: S · Depends: — · Files: `lib/src/app/state/app_controller.dart`, `lib/src/core/models/music_models.dart`

**Why**: `_saveDownloadHistory` (app_controller) only ever prepends the newest entry and
filters the same `downloadSourceKey`, so the list under the `download_history_v1`
preference grows without bound — one entry per unique link, forever. It is written on
every download start via `jsonEncode`, and `SharedPreferences` keeps the whole string in
memory. Heavy users pay a growing write on each download and a growing parse at launch.

**Acceptance criteria**:
- [ ] history is trimmed to a fixed maximum (suggest 200 entries, newest first)
- [ ] the trim happens on write, so an oversized legacy list self-heals at the next download
- [ ] a unit test asserts the cap and that the newest entry survives
- [ ] `DownloadHistoryPage` still shows the full retained list

**Agent instructions**:
1. Add a `const _kMaxDownloadHistory = 200;` next to `_kDownloadHistory` and apply `.take(...)` in `_saveDownloadHistory` before persisting.
2. Extend `test/live_controller_regression_test.dart` (history group) with a cap test.
3. Leave `clearDownloadHistory` untouched — it already writes `[]`.

**Verification**: `flutter test test/live_controller_regression_test.dart`.
**Risks/rollback**: users lose the oldest links past the cap; that is the intended trade. Revert = remove the `.take(...)`.

### TASK-03 Recover source links for pre-`sourceUrl` downloads
Priority: P3 · Effort: M · Depends: — · Files: `lib/src/app/state/app_controller.dart`

**Why**: `Track.sourceUrl` is new, so older manifests have none. `_trackSourceUrl` back-fills
a link only when `artworkUrl` is an `i.ytimg.com` URL whose second path segment is an
11-character video id. Downloads saved without that artwork keep no link at all, so they
never appear in the recovered history and cannot be re-fetched from Settings → Download
history.

**Acceptance criteria**:
- [ ] the coverage gap is measured on a real device library (how many downloaded tracks resolve to null)
- [ ] either a second recovery source is implemented, or the limitation is written into `docs/storage.md` and the empty state explains it
- [ ] no duplicate library entries are created by whatever recovery lands

**Agent instructions**:
1. Check whether the downloader persists the source URL anywhere else (sidecar metadata, file tags) before writing new recovery code.
2. If nothing exists, prefer documenting over guessing — a wrong link re-downloads the wrong song.
3. HUMAN-GATE: measuring against the owner's real library on device.

**Verification**: targeted unit tests around `_trackSourceUrl`; manual check on device.
**Risks/rollback**: a bad heuristic maps a track to someone else's video. Keep the strict 11-character id check.

### TASK-04 `android.yml` CI
Priority: P3 · Effort: M · Depends: — · Files: `.github/workflows/android.yml`

**CORRECTION (2026-09-20)**: this task was seeded DROPPED on a stale fact. The removal
(`0c06f8b revert: remove Android CI`) was reverted by the owner in
`39a2654 ci: enable auto-build on push for iOS and Android workflows`. `android.yml` has
been tracked and green ever since — `gh run list` shows Android runs succeeding for every
release from 1.4.0 to the 2026-09-19 main push (run `35466858492`, 8m54s, success).
Nothing to build; the task is DONE and kept only so the wrong note is not re-derived.

**Current shape**: `ubuntu-latest`, JDK 17 temurin, `flutter build apk --release
--no-tree-shake-icons --android-skip-build-dependency-validation`, ABI `arm64-v8a`,
artifact + release asset `monolith.apk`. Signing weakness tracked as TASK-07.

### TASK-06 Publish releases only from a `v*` tag
Priority: P1 · Effort: S · Depends: — · Files: `.github/workflows/ios.yml`, `.github/workflows/android.yml`

**Why**: both workflows trigger on pushes to `main` as well as on `v*` tags, and the
`Extract app version` step derived the release tag from `pubspec.yaml` whenever the ref
was not a tag. A push to `main` without a version bump therefore resolved to the
*already published* tag and `softprops/action-gh-release` replaced that release's assets
in place. This happened on 2026-09-19: the `v1.4.4` release (published 2026-09-10) had
its `monolith.ipa` and `monolith.apk` overwritten at 20:20 and 20:24 UTC with binaries
built from unreleased `main`.

**Done 2026-09-20**: `Extract app version` replaced with `Resolve release tag`, which
publishes only for `refs/tags/v*` or an explicit `workflow_dispatch` tag input, rejects a
tag that does not match `pubspec.yaml`, and passes the dispatch input through an `env:`
var rather than interpolating it into the shell. Main pushes still build and upload the
7-day workflow artifact.

**Verification**: both files parse (`yaml.safe_load`); `publish` gate is
`steps.app_version.outputs.publish == 'true'` in both. Confirmed end-to-end by the
`v1.4.5` tag run.
**Risks/rollback**: a tag whose `pubspec.yaml` was not bumped now fails the job loudly
instead of silently clobbering. Revert = restore the previous two steps.

### TASK-07 Android CI signs every build with a throwaway key
Priority: P1 · Effort: M · Depends: — · Files: `.github/workflows/android.yml`, `android/app/build.gradle.kts`

**Why**: `android/app/build.gradle.kts` has
`release { signingConfig = signingConfigs.getByName("debug") }`, and `android.yml`
creates that debug keystore on the runner with `keytool -genkey` whenever
`~/.android/debug.keystore` is absent. Nothing caches `~/.android` between runs, so the
release APK is signed by **whatever certificate that ephemeral runner held** — freshly
generated when the image has none, and free to change whenever GitHub rebuilds the runner
image. It is also not the Windows dev machine's debug key. Android refuses to install
over an app signed by a different certificate, so a sideloaded upgrade can fail with
`INSTALL_FAILED_UPDATE_INCOMPATIBLE` / "App not installed" and the in-app updater
(`AppUpdateService`, which downloads the release APK) cannot complete — the user has to
uninstall first and loses app data.

**Not yet measured**: the signer SHA-256 of the published `v1.4.3` and `v1.4.4` APKs was
not compared — the release downloads stalled on 2026-09-20. Do that first; it decides
whether this is already breaking users or only a latent risk.

**Acceptance criteria**:
- [ ] every future release APK is signed by one stable certificate
- [ ] the signing key is never committed — secret-stored and decoded at build time
- [ ] `docs/SIDELOADING.md` states plainly that upgrading across the key change needs an uninstall
- [ ] the signer is verifiable: `keytool -printcert -jarfile monolith.apk` SHA-256 matches between two consecutive releases

**Agent instructions**:
1. Generate a release keystore locally, once, and keep it out of the repo.
2. HUMAN-GATE: creating the `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEY_ALIAS`,
   `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_PASSWORD` repository secrets.
3. Add a `release` signing config in `build.gradle.kts` reading from
   `key.properties`, written by the workflow from the secrets; keep the debug
   fallback for local builds so a clone without secrets still builds.
4. Drop the `keytool -genkey` step once the real key is wired.

**Verification**: build two APKs from two runs; compare `keytool -printcert -jarfile`
SHA-256; install one over the other on a device.
**Risks/rollback**: the key becomes unrecoverable if lost — every future update breaks.
Back it up offline before switching. Existing installs still need one uninstall to cross
from throwaway keys to the stable key; say so in the release notes.

### TASK-08 `v1.4.4` release assets no longer match the `v1.4.4` tag
Priority: P2 · Effort: S · Depends: TASK-06 · Files: — (GitHub release, not code)

**Why**: fallout of TASK-06. `gh release view v1.4.4` shows the release published
2026-09-10 but `monolith.apk` updated 2026-09-19T20:24:32Z and `monolith.ipa`
2026-09-19T20:20:01Z — both built from `main` at `878420d`, which is 1.4.5 code. Anyone
who downloaded `v1.4.4` after that date got binaries that do not correspond to the tag.

**Blocked**: waiting on an owner decision — this is a published-artifact change.

**Agent instructions**:
1. HUMAN-GATE: decide between (a) rebuilding 1.4.4 from tag `v1.4.4` and re-uploading, or
   (b) leaving the binaries and adding a note to the `v1.4.4` release body.
2. Option (b) is cheaper and honest; option (a) requires a `workflow_dispatch` run against
   the `v1.4.4` ref, which the new pubspec/tag match check will accept because that tree
   still says `1.4.4+13`.
**Verification**: asset `updatedAt` and the release body agree about what the binaries are.
**Risks/rollback**: re-uploading changes checksums users may have recorded.

### TASK-09 Version string is duplicated across four files
Priority: P3 · Effort: S · Depends: — · Files: `pubspec.yaml`, `lib/src/core/services/app_update_service.dart`, `README.md`, `test/songs_tab_and_gestures_test.dart`

**Why**: a release needs `version:` in `pubspec.yaml`, `AppUpdateService.currentVersion`,
the README banner and the assertion in `songs_tab_and_gestures_test.dart` all moved by
hand. Miss `currentVersion` and the in-app updater offers the running version as an
update; miss `pubspec.yaml` and the new tag-match check fails the release build.

**Acceptance criteria**:
- [ ] one source of truth for the version at runtime
- [ ] the test asserts agreement rather than a hardcoded literal

**Agent instructions**:
1. Prefer `package_info_plus` (already an indirect dependency via the Flutter
   ecosystem — confirm before adding) or a generated constant over a second literal.
2. If a literal must stay, make the test read `pubspec.yaml` and compare, so drift fails
   CI instead of shipping.
**Verification**: `flutter test test/songs_tab_and_gestures_test.dart` fails when
`pubspec.yaml` and `currentVersion` disagree.
**Risks/rollback**: reading `pubspec.yaml` at test time depends on the working directory;
use `Directory.current` explicitly.

### TASK-05 Custom shuffle/repeat on the iOS Lock Screen
Priority: P3 · Effort: M · Depends: — · Files: `lib/src/core/services/`

**Why**: the standard iOS Lock Screen transport card is owned by iOS. Monolith cannot add
custom shuffle/repeat buttons to it through the supported media APIs (documented in the
CHANGELOG `Unreleased — 2026-09-19` section). In-app controls remain the supported path.

**Dropped**: platform limitation, not a defect. Re-open only if Apple exposes the control.
