# Monolith

![Monolith hero graphic](docs/assets/readme-hero.svg)

Monolith is an offline-first Flutter music player built for local listening, managed downloads, playlist control, and system-grade playback surfaces across Android and iOS.

The project is structured to keep platform UI parity high while still allowing each platform to expose the native behaviors users expect, including media-library access, background playback metadata, lock-screen controls, Control Center integration, and Android media notification transport controls.

| Area | Details |
| --- | --- |
| App identity | Monolith uses the app icon from `branding/app_icon_source.png` and a system-themed visual language inspired by the Zephyr references. |
| Playback surfaces | Android media deck, lock screen controls, headset media buttons, iOS lock screen, and iOS Control Center. |
| Download model | Monolith is positioned around a yt-dlp-oriented YouTube music acquisition workflow; the current embedded mobile implementation uses `youtube_explode_dart` instead of bundling `yt-dlp` binaries directly. |
| Current iOS focus | Jailbroken iOS 16. |
| Core stack | Flutter, `just_audio`, `just_audio_background`, `audio_session`, `on_audio_query`, and controller-driven app state. |

For iOS right now, the active device focus is jailbroken iOS 16 while the broader public-safe Windows-to-iPhone workflow remains on standby.

## <img src="docs/assets/icons/ic-overview.svg" width="20" height="20" alt=""> Overview

![Monolith product overview](docs/assets/product-overview.svg)

## <img src="docs/assets/icons/ic-product.svg" width="20" height="20" alt=""> Product Surface

Monolith currently centers around three primary surfaces:

- Library: browse imported and on-device audio, manage playlists, and organize listening sessions.
- Downloads: fetch and manage offline audio files, filter local items, and review download activity.
- Search: surface tracks and jump directly into playback.

Playback is powered by `just_audio`, with `just_audio_background` handling system-facing media metadata and `audio_session` pinning the app to a music-friendly playback session so the current track can surface correctly on iOS lock screen, iOS Control Center, and Android's media notification deck.

## <img src="docs/assets/icons/ic-pillars.svg" width="20" height="20" alt=""> Experience Pillars

| Pillar | What it delivers |
| --- | --- |
| Offline listening | Downloaded and imported tracks remain available as a local-first library for playback without depending on a live stream session. |
| Unified player | A single controller-driven playback layer keeps queue state, metadata, and transport behavior consistent across Library, Downloads, Search, and the full-screen Player. |
| System integration | Android notification controls, headset media buttons, iOS lock screen, and iOS Control Center are treated as first-class playback surfaces. |
| Library ownership | Imports, playlists, manifest-backed downloads, and local reconciliation are built around a permanent collection model rather than disposable streaming sessions. |

## <img src="docs/assets/icons/ic-download.svg" width="20" height="20" alt=""> Download Pipeline

Monolith downloads music from YouTube-source inputs for offline playback and local library management.

- The product workflow is described in yt-dlp terms because the downloader surface is shaped around that class of acquisition flow.
- The current checked-in mobile implementation uses `youtube_explode_dart` as the active backend rather than shipping `yt-dlp` binaries inside the app.
- Downloaded tracks are persisted locally, reconciled into manifest-backed storage, and surfaced back through the Library and Player experiences.

## <img src="docs/assets/icons/ic-capabilities.svg" width="20" height="20" alt=""> Core Capabilities

- Shared Flutter UI for Android and iOS.
- Local device-library import using `on_audio_query`.
- YouTube-source music downloads aligned with a yt-dlp-style offline acquisition workflow.
- Offline track persistence and manifest-backed download storage.
- Download workflow with progress, pause, cancel, retry, and fatal-error handling.
- Playlist creation and playlist membership management inside the Library surface.
- Full-screen player with animated artwork, progress reporting, repeat handling, and queue navigation.
- Background playback metadata for Android notifications and iOS lock-screen controls.
- Light and dark themes driven by the app controller.

## <img src="docs/assets/icons/ic-architecture.svg" width="20" height="20" alt=""> Architecture Summary

Monolith uses a controller-driven architecture with a thin app shell and feature-oriented presentation layers.

![Monolith architecture summary](docs/assets/architecture-map.svg)

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

## <img src="docs/assets/icons/ic-repository.svg" width="20" height="20" alt=""> Repository Layout

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

## <img src="docs/assets/icons/ic-getting-started.svg" width="20" height="20" alt=""> Getting Started

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

## <img src="docs/assets/icons/ic-workflow.svg" width="20" height="20" alt=""> Development Workflow

![Monolith development workflow](docs/assets/development-workflow.svg)

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
- The current downloader flow targets YouTube-source audio acquisition and is described in yt-dlp terms for product direction, while the in-app implementation currently uses `youtube_explode_dart`.
- The repository keeps local plugin overrides in `third_party/` to avoid AGP and Kotlin drift.

## <img src="docs/assets/icons/ic-platform.svg" width="20" height="20" alt=""> Platform Focus

### Android

- Supports device-library access, downloads, media notifications, and lock-screen controls.
- Release builds are shrunk and ABI-filtered to reduce package size.

### iOS

- Uses the shared Flutter UI.
- The current device-side focus is jailbroken iOS 16.
- Prompts at startup for Apple Music and media-library import when supported.
- Requires macOS tooling for build and signing.
- The public-safe GitHub standby flow is prepared, but real-world iOS iteration is currently centered on jailbroken iOS 16 hardware.

## <img src="docs/assets/icons/ic-ios.svg" width="20" height="20" alt=""> iOS Build Notes

- The iOS workflow is `workflow_dispatch` only, so pushing the repo will not auto-trigger macOS builds.
- The prepared workflow uploads an unsigned IPA artifact.
- No signing material, provisioning profiles, certificates, or local build artifacts are committed.
- The repository is ready for a public GitHub repo as long as you do not add secrets, signing files, or generated release/debug artifacts.

See `docs/development.md` for the full development and validation guide.

## <img src="docs/assets/icons/ic-playback.svg" width="20" height="20" alt=""> Playback And Media Integration

Monolith now initializes `just_audio_background` during startup and attaches a `MediaItem` tag whenever a playable track is loaded. This enables:

- Android media notifications
- lock-screen metadata and transport controls
- headset and system media-button integration
- iOS lock-screen and Control Center now-playing information

Platform requirements are committed in the repository:

- Android manifest permissions and media service declarations
- iOS `UIBackgroundModes` audio entry and an explicit music audio-session configuration

See `docs/media-playback.md` for implementation details and troubleshooting guidance.

## <img src="docs/assets/icons/ic-verify.svg" width="20" height="20" alt=""> Verification

Focused widget regression suite:

```sh
flutter test test/widget_test.dart
```

Full test suite:

```sh
flutter test
```

The current widget suite is used as the primary fast validation path for shell navigation, downloads behavior, and controller-backed UI flows.

## <img src="docs/assets/icons/ic-verify.svg" width="20" height="20" alt=""> Testing

## <img src="docs/assets/icons/ic-docs.svg" width="20" height="20" alt=""> Documentation Map

- `docs/architecture.md`: application structure and data flow.
- `docs/development.md`: setup, commands, validation, and workflow notes.
- `docs/media-playback.md`: background playback and system media integration.

## <img src="docs/assets/icons/ic-troubleshoot.svg" width="20" height="20" alt=""> Troubleshooting

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
