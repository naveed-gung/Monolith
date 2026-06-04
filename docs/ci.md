# CI & Dependabot

This repo's automation, and why the bot runs you sometimes see are normal.

## Workflows

| File | Trigger | What it does |
| --- | --- | --- |
| `.github/workflows/ios.yml` | push of a `v*` tag (or manual) | Builds the **unsigned IPA**, uploads `monolith.ipa` to the tag's GitHub Release. macOS runner. |

**iOS is the ONLY thing CI builds.** There is deliberately **no Android
workflow** — the **APK is built locally on the Windows dev machine**
(`flutter build apk --release --no-tree-shake-icons`) and uploaded to the
release by hand (`gh release upload v<x.y.z> monolith.apk`). This avoids
duplicate/competing runs and keeps Android off CI entirely.

The iOS build needs `--no-tree-shake-icons` because of the vendored
`phosphor_flutter` 3.44 patch (icon constructors become `static final`, which
the icon tree-shaker rejects). The local Android release APK is signed with the
**debug keystore** — fine for a sideloaded build, and we never commit a real
release key (see `SECURITY.md`).

## Dependabot — what those scheduled bot runs are

`.github/dependabot.yml` enables automated dependency-update PRs for two
ecosystems:

- **`pub`** — Dart/Flutter packages in `pubspec.yaml`
- **`github-actions`** — the action versions pinned in the workflows above

**The runs labelled "Dependabot Updates #N" are Dependabot's own
dependency-resolution jobs, not app builds.** GitHub schedules them, so an
off-hours UTC timestamp (e.g. ~04:55 UTC) shows up as morning in GMT+3. Short
durations (≈40s–2m) are normal — they only resolve versions and open/close PRs;
they never build or touch a release.

**Deleting a Dependabot *run* only removes a log entry.** Nothing in the repo,
the code, or any release is affected, and it neither needs nor can be undone.

The config lives at `.github/dependabot.yml`. As of 1.0.4 it runs **monthly**
(was weekly) with minor/patch updates **grouped** into a single PR per
ecosystem, so there's far less noise. Security updates still come through
immediately regardless of the schedule.

## Why we don't bulk-merge Dependabot PRs

The project has **vendored plugin overrides** (`third_party/file_selector_android`,
`third_party/on_audio_query_android`) and the `phosphor_flutter` 3.44 patch. A
blind pub bump — especially anything touching `phosphor_flutter`,
`file_selector`, `on_audio_query`, `just_audio`, or the Gradle toolchain — can
break the build. Each PR is triaged individually; pub bumps are only merged once
`flutter analyze && flutter test && flutter build apk --release` are clean.

### Triage — 7 open PRs (as of 1.0.4)

| PR | Bump | Decision | Reason |
| --- | --- | --- | --- |
| #16 | `actions/checkout` 4 → 6 | **merge** | Standard infra action; doesn't touch the app build or release content. |
| #15 | `actions/cache` 4 → 5 | **merge** | Same — cache-only, safe major bump. |
| #14 | `actions/upload-artifact` 4 → 7 | **merge** | Artifact upload only; the breaking change was v3→v4, which we're already past. |
| #17 | `softprops/action-gh-release` 2 → 3 | **hold** | This action *writes the release*. A major bump here can change release-asset behaviour; verify on a throwaway test tag before merging. |
| #22 | `youtube_explode_dart` 2.5.3 → 3.1.0 | **hold** | Core download engine; a major API change can break the download path. Needs a full build + manual download test. |
| #23 | `connectivity_plus` 6.1.2 → 7.1.1 | **hold** | `pubspec.yaml` deliberately pins `>=6.0.0 <6.1.3`; 7.x conflicts with that pin and changes the API. Revisit the pin first. |
| #24 | `share_plus` 10.1.4 → 13.1.0 | **hold** | Three majors at once; likely raises min SDK / AGP requirements. Needs a clean `flutter build apk --release` before merging. |

The three `actions/*` merges are done deliberately (not bulk) because they're
release-path-independent. The four holds stay open until they can be built and
verified — don't merge them just to clear the list.
