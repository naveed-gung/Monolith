# CI & Dependabot

This repo's automation, and why the bot runs you sometimes see are normal.

## Workflows

| File | Trigger | What it does |
| --- | --- | --- |
| `.github/workflows/ios.yml` | push to `main`, push of a `v*` tag, or manual | Builds the **unsigned IPA** on `macos-15`. Always uploads `monolith.ipa` as a 7-day workflow artifact; publishes it to the GitHub Release **only for a tag**. |
| `.github/workflows/android.yml` | push to `main`, push of a `v*` tag, or manual | Builds the **release APK** on `ubuntu-latest`. Always uploads `monolith.apk` as a 7-day workflow artifact; publishes it to the GitHub Release **only for a tag**. |

**Both platforms build on CI.** A push to `main` is a build check — you get
downloadable artifacts, nothing is released. A `v*` tag is the release: both
workflows attach their binary to the same release and `append_body: true` means
each one appends its own install notes.

### Releasing

1. Bump `version:` in `pubspec.yaml` **and** `AppUpdateService.currentVersion`
   (`lib/src/core/services/app_update_service.dart`) — the in-app updater
   compares against the latter.
2. Move the CHANGELOG's top section from `Unreleased` to `## [x.y.z] — <date>`.
3. Commit, push `main`, then `git tag vx.y.z && git push origin vx.y.z`.

The **Resolve release tag** step refuses to publish when the tag does not match
`pubspec.yaml`, and skips publishing entirely when there is no tag. This exists
because it used to resolve the tag from `pubspec.yaml` on *every* push to
`main`: on 2026-09-19 a main push with an unbumped `1.4.4+13` re-published into
the existing `v1.4.4` release and **overwrote its `monolith.apk` and
`monolith.ipa` in place**, so the tag no longer matched the binaries behind it.

`workflow_dispatch` takes an optional `tag` input — supply `vx.y.z` to
re-publish that release, leave it blank for a build-only run.

The iOS build needs `--no-tree-shake-icons` because of the vendored
`phosphor_flutter` 3.44 patch (icon constructors become `static final`, which
the icon tree-shaker rejects). The Android job passes the same flag, plus
`--android-skip-build-dependency-validation`. The release APK is signed with the
**debug keystore** (`android/app/build.gradle.kts` →
`release { signingConfig = signingConfigs.getByName("debug") }`) — fine for a
sideloaded build, and we never commit a real release key (see `SECURITY.md`).
That signing key is **not a key this project owns**. `android.yml` runs
`keytool -genkey` when the runner has no `~/.android/debug.keystore`, and nothing
caches that file between runs, so the certificate is whatever the ephemeral
runner happened to hold — it can change when GitHub rebuilds its runner image,
and it differs from the debug keystore on the Windows dev machine. Android
refuses to install an APK over an installed app signed by a different
certificate, so a sideloaded upgrade can fail with "App not installed" and force
an uninstall (losing app data). Check before assuming an upgrade will work:

```sh
keytool -printcert -jarfile monolith.apk   # compare the SHA-256 between releases
```

Tracked as TASK-07 in `docs/agent/01-roadmap.md` — the fix is a real release key
held in repository secrets.

## Dependabot — disabled on purpose

There is **no `.github/dependabot.yml`** and there shouldn't be one. It was
removed in 1.0.4 because its scheduled "Dependabot Updates" resolution runs and
the version-bump PRs it opened were unwanted noise — the only automation this
repo wants is the iOS IPA build on a `v*` tag.

Dependency bumps are done **manually** when needed: edit `pubspec.yaml`, run
`flutter pub get && flutter analyze && flutter test && flutter build apk --release`,
and commit. This matters because the project has **vendored plugin overrides**
(`third_party/file_selector_android`, `third_party/on_audio_query_android`) and
the `phosphor_flutter` 3.44 patch, so a blind bump of `phosphor_flutter`,
`file_selector`, `on_audio_query`, `just_audio`, or the Gradle toolchain can
break the build.

> If GitHub still shows "Dependabot" runs after this, also turn off
> **Settings → Code security → Dependabot version updates / security updates**,
> which is a repo setting separate from the deleted YAML.
