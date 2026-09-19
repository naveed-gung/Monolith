<!-- AGENT NOTE: Before ending your session, update the Status table below if you
touched anything related, bump last-verified, and append to SESSIONS.md.
Rules: docs/agent/PROTOCOL.md -->
---
doc: 01-roadmap
last-verified: 2026-09-19
verified-by: claude-code
---

# Monolith — roadmap & open work

Seeded 2026-09-19 while reviewing the download-history / playback-order batch. Every
task below came from reading the code or running the tooling — no filler.

## Status

| ID | Title | Priority | Effort | Status | Last touched |
|----|-------|----------|--------|--------|--------------|
| TASK-01 | Exclude probe directories from `flutter analyze` | P2 | S | TODO | 2026-09-19 |
| TASK-02 | Cap the persisted download history | P2 | S | TODO | 2026-09-19 |
| TASK-03 | Recover source links for pre-`sourceUrl` downloads | P3 | M | TODO | 2026-09-19 |
| TASK-04 | Add `android.yml` CI | P3 | M | DROPPED | 2026-09-19 |
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

### TASK-04 Add `android.yml` CI
Priority: P3 · Effort: M · Depends: — · Files: `.github/workflows/`

**Why**: an Android workflow was added during the 1.0.4 batch and removed again by the
owner — CI is iOS-only, APKs are built locally on Windows and uploaded with
`gh release upload`.

**Dropped**: do not re-add an Android workflow. Raise it with the owner first if the
build story changes.

### TASK-05 Custom shuffle/repeat on the iOS Lock Screen
Priority: P3 · Effort: M · Depends: — · Files: `lib/src/core/services/`

**Why**: the standard iOS Lock Screen transport card is owned by iOS. Monolith cannot add
custom shuffle/repeat buttons to it through the supported media APIs (documented in the
CHANGELOG `Unreleased — 2026-09-19` section). In-app controls remain the supported path.

**Dropped**: platform limitation, not a defect. Re-open only if Apple exposes the control.
