# Monolith

Monolith is a Flutter music player built around an offline-first mobile listening experience. The app combines device-library import, managed downloads, playlists, immersive playback UI, and shared Android/iOS presentation in a single codebase.

The project is structured to keep platform UI parity high while still allowing each platform to expose the native behaviors users expect, including media-library access, background playback metadata, lock-screen controls, and Android notification transport controls.

![Monolith product overview](docs/assets/product-overview.svg)

## Product Overview

Monolith currently centers around three primary surfaces:

- Library: browse imported and on-device audio, manage playlists, and organize listening sessions.
- Downloads: fetch and manage offline audio files, filter local items, and review download activity.
- Search: surface tracks and jump directly into playback.

Playback is powered by `just_audio`, with `just_audio_background` handling system-facing media metadata and `audio_session` pinning the app to a music-friendly playback session so the current track can surface correctly on iOS lock screen, iOS Control Center, and Android's media notification deck.

## Core Capabilities

- Shared Flutter UI for Android and iOS.
- Local device-library import using `on_audio_query`.
- Offline track persistence and manifest-backed download storage.
- Download workflow with progress, pause, cancel, retry, and fatal-error handling.
- Playlist creation and playlist membership management inside the Library surface.
- Full-screen player with animated artwork, progress reporting, repeat handling, and queue navigation.
- Background playback metadata for Android notifications and iOS lock-screen controls.
- Light and dark themes driven by the app controller.

## Architecture Summary

Monolith uses a controller-driven architecture with a thin app shell and feature-oriented presentation layers.

- `lib/main.dart`: bootstraps Flutter bindings and initializes background media support.
- `lib/src/app/`: application wiring, top-level state, and theming.
- `lib/src/core/`: shared models, services, demo data, and reusable widgets.
- `lib/src/features/`: feature-specific presentation for Library, Downloads, Player, Search, Settings, and the app shell.
- `android/` and `ios/`: platform runners and platform-specific capabilities.
- `third_party/`: vendored package overrides needed for Android toolchain compatibility.

The main orchestration point is `MonolithController` in `lib/src/app/state/app_controller.dart`. It owns:

- app navigation state
- current playback state and player bindings
- device-library refresh
- downloads and import persistence
- playlist state
- theme state

More detail is available in `docs/architecture.md`.

## Project Layout

```text
lib/
 main.dart
 src/
  app/
  core/
  features/
android/
ios/
reference/
test/
third_party/
```

Important folders:

- `reference/`: visual references used to guide the UI direction.
- `test/`: widget-level regression coverage for the shell and core flows.
- `third_party/on_audio_query_android`: vendored Android plugin override required for current Android Gradle Plugin compatibility.
- `third_party/file_selector_android`: vendored override used to keep build tooling aligned with the repository toolchain.

## Getting Started

### Prerequisites

- Flutter SDK compatible with Dart `^3.10.1`
- Android SDK for Android builds and emulator testing
- Xcode and CocoaPods on macOS for iOS builds

### Install Dependencies

```sh
flutter pub get
```

### Run The App

```sh
flutter run
```

To target a specific device:

```sh
flutter devices
flutter run -d <device-id>
```

## Development Workflow

Typical local loop:

```sh
flutter pub get
flutter test test/widget_test.dart
flutter run
```

Useful commands:

```sh
flutter analyze
flutter build apk
flutter build ios
```

Notes:

- `flutter build ios` must be executed on macOS.
- The downloader is not intended for web builds.
- The repository keeps local plugin overrides in `third_party/` to avoid AGP and Kotlin drift.

## Windows To iPhone Standby

Monolith is now prepared for a public-safe, manual-only GitHub Actions flow that can later be used with MobAI's `ios-builder` tooling from Windows.

- The iOS workflow is `workflow_dispatch` only, so pushing the repo will not auto-trigger macOS builds.
- The prepared workflow uploads an unsigned IPA artifact using the generic artifact name `ipa`, which aligns with `ios-builder`'s expected download flow.
- No signing material, provisioning profiles, certificates, or local build artifacts are committed.
- The repository is ready for a public GitHub repo as long as you do not add secrets, signing files, or generated release/debug artifacts.

See `docs/ios-builder-setup.md` for the standby setup and later activation steps.

See `docs/development.md` for the full development and validation guide.

## Playback And Media Integration

Monolith now initializes `just_audio_background` during startup and attaches a `MediaItem` tag whenever a playable track is loaded. This enables:

- Android media notifications
- lock-screen metadata and transport controls
- headset and system media-button integration
- iOS lock-screen and Control Center now-playing information

Platform requirements are committed in the repository:

- Android manifest permissions and media service declarations
- iOS `UIBackgroundModes` audio entry and an explicit music audio-session configuration

See `docs/media-playback.md` for implementation details and troubleshooting guidance.

## Testing

Focused widget regression suite:

```sh
flutter test test/widget_test.dart
```

Full test suite:

```sh
flutter test
```

The current widget suite is used as the primary fast validation path for shell navigation, downloads behavior, and controller-backed UI flows.

## Platform Notes

### Android

- Supports device-library access, downloads, media notifications, and lock-screen controls.
- Release builds are shrunk and ABI-filtered to reduce package size.

### iOS

- Uses the shared Flutter UI.
- Prompts at startup for Apple Music and media-library import when supported.
- Requires macOS tooling for build and signing.

## Documentation Map

- `docs/architecture.md`: application structure and data flow.
- `docs/development.md`: setup, commands, validation, and workflow notes.
- `docs/ios-builder-setup.md`: public-safe Windows-to-iPhone standby setup for later MobAI testing.
- `docs/media-playback.md`: background playback and system media integration.

## Troubleshooting

### Lock screen or Android media notification does not appear

- Confirm the app is playing a track that has a valid local file path.
- Verify `flutter pub get` has installed `just_audio_background`.
- Confirm the Android app was rebuilt after manifest changes.
- On iOS, verify the app has been launched from a build that includes `UIBackgroundModes` audio support.

### Downloaded tracks disappear

- Monolith stores downloaded-track metadata in a manifest under the app documents directory.
- Missing files are automatically pruned from the manifest during load.

### Android build behaves inconsistently after dependency changes

- Re-run `flutter pub get`.
- Check the vendored plugin overrides in `third_party/`.
- Review `docs/development.md` for current repository-specific build notes.
