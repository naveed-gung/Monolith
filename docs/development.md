# Development Guide

![Development workflow](assets/development-workflow.svg)

The workflow above reflects the repository's preferred feedback loop: dependency sync, focused widget validation, then packaging checks when platform wiring changes.

## Environment

Monolith is a Flutter project targeting Android and iOS.

Required tooling:

- Flutter SDK with Dart `^3.10.1`
- Android SDK and an emulator or physical device for Android testing
- macOS, Xcode, and CocoaPods for iOS builds

## Initial Setup

From the repository root:

```sh
flutter pub get
```

If you are switching branches after dependency or plugin changes, run the same command again before building.

## Common Commands

Run locally:

```sh
flutter run
```

Run the focused widget regression suite:

```sh
flutter test test/widget_test.dart
```

Run the full test suite:

```sh
flutter test
```

Static analysis:

```sh
flutter analyze
```

Android build:

```sh
flutter build apk
```

iOS build:

```sh
flutter build ios
```

## Repository-Specific Notes

### Vendored Android plugin overrides

This repository intentionally overrides some Android plugins from local paths under `third_party/`.

Current reasons include:

- aligning Android Gradle Plugin and Kotlin versions with the app toolchain
- keeping `on_audio_query_android` compatible with the current AGP setup
- avoiding slow or incompatible toolchain downloads caused by upstream plugin configuration drift

Do not remove these overrides casually. Review the local package contents and build impact first.

### Android NDK

The Android app is configured against NDK `28.2.13676358` in `android/app/build.gradle.kts` because the local `27.0.12077973` installation was previously observed as incomplete.

### iOS build limitations on Windows

You can edit and validate shared Flutter UI from Windows, but you cannot produce an iOS build artifact locally without macOS.

## Validation Workflow

Recommended order after code changes:

1. `flutter pub get` if dependencies changed
2. `flutter test test/widget_test.dart`
3. `flutter analyze` for broader static validation when relevant
4. `flutter build apk` if Android platform files, plugins, or manifests changed

For media-session work that touches iOS behavior, add a final device check on macOS or a signed iPhone build after the shared Flutter validation passes.

## Public GitHub Standby

This repository is now set up so you can later publish it as a public GitHub repo without immediately leaking secrets or triggering iOS Actions.

- `.github/workflows/ios.yml` is manual-only.
- `.gitignore` excludes IPA files, provisioning profiles, certificates, keystores, and local environment files.
- The intended `ios-builder` configuration is stored as a template in `builder.json.example`, not as a secret-bearing live config.

That means you can commit the preparation files first, review them, and only later create the public repo and manually dispatch the workflow when you are ready.

## Files Worth Knowing

- `lib/src/app/state/app_controller.dart`: central app behavior
- `lib/src/features/shell/presentation/music_shell.dart`: shell and navigation
- `lib/src/features/player/presentation/player_page.dart`: full-screen playback UI
- `lib/src/features/downloads/presentation/downloads_page.dart`: downloads and offline library view
- `lib/src/core/services/download_store.dart`: download persistence and artifact cleanup
- `lib/src/core/services/local_media_service.dart`: device-library query integration

## Troubleshooting

### Widget tests hang or behave unexpectedly

- Prefer controller injection in tests.
- Refresh the library before pumping widget trees when the test depends on populated state.
- Avoid fake file paths that trigger real player loading during widget tests.

### Android build slows down after plugin changes

- Confirm local overrides are still active in `pubspec.yaml`.
- Check whether a dependency pulled a newer AGP or Kotlin version unexpectedly.

### Media import crashes after granting permission

- Review the vendored `third_party/on_audio_query_android` package before updating it. This repository already carries a permission-flow stability fix.
