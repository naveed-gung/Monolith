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
