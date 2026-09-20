<!-- AGENT NOTE: Before ending your session, update the Status table below if you
touched anything related, bump last-verified, and append to SESSIONS.md.
Rules: docs/agent/PROTOCOL.md -->
---
doc: 01-roadmap
last-verified: 2026-09-20
verified-by: claude-code
---

# Monolith — roadmap & open work

Seeded 2026-09-19 while reviewing the download-history / playback-order batch. Every
task below came from reading the code or running the tooling — no filler.

## Status

| ID | Title | Priority | Effort | Status | Last touched |
|----|-------|----------|--------|--------|--------------|
| TASK-07 | Android CI signs every build with a throwaway key | P1 | M | TODO | 2026-09-20 |
| TASK-01 | Exclude probe directories from `flutter analyze` | P2 | S | TODO | 2026-09-19 |
| TASK-02 | Cap the persisted download history | P2 | S | TODO | 2026-09-19 |
| TASK-08 | `v1.4.4` release assets no longer match the `v1.4.4` tag | P2 | S | BLOCKED | 2026-09-20 |
| TASK-03 | Recover source links for pre-`sourceUrl` downloads | P3 | M | TODO | 2026-09-19 |
| TASK-09 | Version string is duplicated across four files | P3 | S | TODO | 2026-09-20 |
| TASK-04 | `android.yml` CI | P3 | M | DONE | 2026-09-20 |
| TASK-06 | Publish releases only from a `v*` tag | P1 | S | DONE | 2026-09-20 |
| TASK-05 | Custom shuffle/repeat on the iOS Lock Screen | P3 | M | DROPPED | 2026-09-19 |

## Tasks

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

**Why**: `release { signingConfig = signingConfigs.getByName("debug") }` and the Linux
runner has no debug keystore, so `android.yml` runs `keytool -genkey` to create one on
every run. `keytool` generates fresh key material each time, and nothing caches
`~/.android`, so **each release APK is signed by a different certificate**. Android
refuses to install an APK over an installed app with a different signer, so sideloaded
upgrades fail with `INSTALL_FAILED_UPDATE_INCOMPATIBLE` / "App not installed" and the
in-app updater (`AppUpdateService`, which downloads the release APK) cannot complete an
update — the user must uninstall first, losing app data.

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
