<!-- AGENT NOTE: Before ending your session, update the Status tables in the docs you
touched, bump last-verified, and append a line to SESSIONS.md.
Rules: docs/agent/PROTOCOL.md -->
---
doc: 00-INDEX
last-verified: 2026-09-19
verified-by: claude-code
---

# Monolith — agent docs index

Agent-maintained knowledge base. Read this file first, every session.

Monolith is an offline-first Flutter music player (Android + iOS) with built-in
downloads. Current version: `1.4.4+13` (`pubspec.yaml`); newest shipped release `1.4.4`
(2026-09-10). CHANGELOG carries an `Unreleased — 2026-09-19` section.

## Doc map

| Doc | Scope | ID prefix |
|-----|-------|-----------|
| [PROTOCOL.md](PROTOCOL.md) | The maintenance contract (read once per session) | — |
| [SESSIONS.md](SESSIONS.md) | Session journal, newest first | — |
| [01-roadmap.md](01-roadmap.md) | All open work: bugs, features, debt | TASK |

Human-facing docs (authoritative, not agent-maintained): `docs/architecture.md`,
`docs/BUILD.md`, `docs/ci.md`, `docs/storage.md`, `docs/media-playback.md`,
`docs/deferred.md`, `docs/ROADMAP.md`, `docs/TROUBLESHOOTING.md`, `docs/SIDELOADING.md`.

## Repo facts (verified 2026-09-19)

- Code lives under `lib/src/**` (feature-first: `app/state`, `core/models`,
  `core/services`, `features/<name>/presentation`, `shared/widgets`).
- Single state holder: `MonolithController extends ChangeNotifier`
  (`lib/src/app/state/app_controller.dart`, ~1700 lines), reached through
  `AppScope.read/watch`. No Riverpod.
- CI: `.github/workflows/ios.yml` only — `v*` tags plus `workflow_dispatch`, `macos-15`,
  unsigned IPA named `monolith.ipa`. Android APKs are built locally on Windows and
  attached with `gh release upload`. No `android.yml` — owner decision (TASK-04).
- `flutter analyze` is clean for `lib/` and `test/`; its 17 remaining warnings all come
  from throwaway probes under `artifacts/audit/`, `build/`, `scripts/` (TASK-01).
- The full `flutter test` suite takes ~15 min on Windows — slow, not hung. Per-file runs
  are seconds.
- Toolchain: Flutter SDK `C:/Users/naveed/develop/flutter`, Android SDK
  `C:/Users/naveed/AppData/Local/Android/Sdk`, AVD `Pixel_10a`.

## Status legend

`TODO` not started · `IN-PROGRESS` someone worked on it, unfinished · `BLOCKED`
needs HUMAN-GATE or dependency · `DONE` verified complete · `DROPPED` won't do.

## Current top priorities (max 5 — keep current)

1. TASK-02 — cap the download-history list before it grows without bound.
2. TASK-01 — keep `flutter analyze` signal clean by excluding probe directories.
3. TASK-03 — recover source links for pre-`sourceUrl` downloads beyond the artwork heuristic.

## Cross-doc dependencies

| Task | Depends on |
|------|------------|
| — | single-doc layout, no cross-doc deps yet |
