# Monolith

![Monolith hero graphic](docs/assets/readme-hero.svg)

**Monolith** is an offline-first Flutter music player built for local listening, managed downloads, playlist control, and system-grade playback surfaces across Android and iOS.

## Why I built this

I got tired of the choice: either manage downloads on Windows and manually transfer files, or rely on some third-party app on my phone with questionable quality and even more questionable permissions. Every existing solution felt like a compromise.

So I thought — if I'm already trusting a third-party app, why not just build my own? At least then it would work exactly how I want, respect my library as *mine*, and actually handle offline playback without nagging me to subscribe to something.

**Monolith is that app.** A personal project that turned into something I actually enjoy using every day.

The project is structured to keep platform UI parity high while still allowing each platform to expose the native behaviors users expect, including media-library access, background playback metadata, lock-screen controls, Control Center integration, and Android media notification transport controls.

| Area | Details |
| --- | --- |
| App identity | Monolith uses the app icon from `branding/app_icon_source.png` and a system-themed visual language inspired by the Zephyr references. |
| Playback surfaces | Android media deck, lock screen controls, headset media buttons, iOS lock screen, and iOS Control Center. |
| Download model | Monolith is positioned around a yt-dlp-oriented YouTube music acquisition workflow; the current embedded mobile implementation uses `youtube_explode_dart` instead of bundling `yt-dlp` binaries directly. |
| Current iOS focus | iOS 16.4+. Primary test device is iOS 16.7. |
| Core stack | Flutter, `just_audio`, `just_audio_background`, `audio_session`, `on_audio_query`, and controller-driven app state. |

## Overview

![Monolith product overview](docs/assets/product-overview.svg)

## Product Surface

Monolith currently centres around three primary surfaces:

- **Library** — browse imported and on-device audio, manage playlists, and organise listening sessions.
- **Downloads** — fetch and manage offline audio files, filter local items, and review download activity.
- **Search** — surface tracks and jump directly into playback.

Playback is powered by `just_audio`, with `just_audio_background` handling system-facing media metadata and `audio_session` pinning the app to a music-friendly playback session so the current track can surface correctly on iOS lock screen, iOS Control Center, and Android's media notification deck.

## Experience Pillars

| Pillar | What it delivers |
| --- | --- |
| Offline listening | Downloaded and imported tracks remain available as a local-first library for playback without depending on a live stream session. |
| Unified player | A single controller-driven playback layer keeps queue state, metadata, and transport behaviour consistent across Library, Downloads, Search, and the full-screen Player. |
| System integration | Android notification controls, headset media buttons, iOS lock screen, and iOS Control Center are treated as first-class playback surfaces. |
| Library ownership | Imports, playlists, manifest-backed downloads, and local reconciliation are built around a permanent collection model rather than disposable streaming sessions. |

## Download Pipeline

Monolith downloads music from YouTube-source inputs for offline playback and local library management.

- The product workflow is described in yt-dlp terms because the downloader surface is shaped around that class of acquisition flow.
- The current checked-in mobile implementation uses `youtube_explode_dart` as the active backend rather than shipping `yt-dlp` binaries inside the app.
- Downloaded tracks are persisted locally, reconciled into manifest-backed storage, and surfaced back through the Library and Player experiences.

## Core Capabilities

- Shared Flutter UI for Android and iOS.
- Local device-library import using `on_audio_query`.
- YouTube-source music downloads aligned with a yt-dlp-style offline acquisition workflow.
- Offline track persistence and manifest-backed download storage.
- Download workflow with progress, pause, cancel, retry, and fatal-error handling.
- Playlist creation and playlist membership management inside the Library surface.
- Full-screen player with animated artwork, progress reporting, repeat handling, and queue navigation.
- Background playback metadata for Android notifications and iOS lock-screen controls.
- Light and dark themes driven by the app controller.
- Storage screen — browse, share, and inspect all downloaded files.

## Architecture Summary

Monolith uses a controller-driven architecture with a thin app shell and feature-oriented presentation layers.

![Monolith architecture summary](docs/assets/architecture-map.svg)

- `lib/main.dart` — bootstraps Flutter bindings and initialises background media support.
- `lib/src/app/` — application wiring, top-level state, and theming.
- `lib/src/core/` — shared models, services, demo data, and reusable widgets.
- `lib/src/features/` — feature-specific presentation for Library, Downloads, Player, Search, Settings, Storage, and the app shell.
- `android/` and `ios/` — platform runners and platform-specific capabilities.
- `third_party/` — vendored package overrides needed for Android toolchain compatibility.

The main orchestration point is `MonolithController` in `lib/src/app/state/app_controller.dart`. It owns app navigation state, current playback state and player bindings, device-library refresh, downloads and import persistence, playlist state, and theme state.

## Repository Layout

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

**Important folders:**

- `reference/` — visual references used to guide the UI direction.
- `test/` — widget-level regression coverage for the shell and core flows.
- `third_party/on_audio_query_android` — vendored Android plugin override required for current Android Gradle Plugin compatibility.
- `third_party/file_selector_android` — vendored override used to keep build tooling aligned with the repository toolchain.

## Getting Started

**Prerequisites**

- Flutter SDK compatible with Dart `^3.10.1`
- Android SDK for Android builds and emulator testing
- Xcode and CocoaPods on macOS for iOS builds

**Install dependencies**

```sh
flutter pub get
```

**Run the app**

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
flutter build apk --release --target-platform android-arm64
flutter build ios --release --no-codesign   # macOS only
```

**Notes:**

- `flutter build ios` must be executed on macOS.
- The downloader is not intended for web builds.
- The repository keeps local plugin overrides in `third_party/` to avoid AGP and Kotlin drift.

## Platform Focus

### Android

- Supports device-library access, downloads, media notifications, and lock-screen controls.
- Release builds are shrunk and ABI-filtered to reduce package size.
- Built locally on Windows and published to GitHub Releases as an arm64 APK.

### iOS

- Uses the shared Flutter UI.
- Minimum deployment target: iOS 16.4. Primary test device: iOS 16.7.
- Prompts at startup for Apple Music and media-library import when supported.
- Requires macOS tooling for build and signing.
- The GitHub Actions workflow builds an unsigned IPA (no Apple Developer Program required) and attaches it to each release. Sideload with AltStore or Sideloadly.

## iOS Build Notes

The iOS workflow (`ios.yml`) triggers automatically on version tags (`v*`).

- Builds an unsigned IPA using `--no-codesign` — no Apple ID or provisioning profile required in CI.
- The unsigned IPA is attached to the corresponding GitHub Release.
- To install on a real device: sideload via AltStore, Sideloadly, or re-sign with your own Apple ID using Xcode.
- No signing material, provisioning profiles, certificates, or local build artifacts are committed.

## Playback and Media Integration

Monolith initialises `just_audio_background` during startup and attaches a `MediaItem` tag whenever a playable track is loaded. This enables:

- Android media notifications
- Lock-screen metadata and transport controls
- Headset and system media-button integration
- iOS lock-screen and Control Center now-playing information

Platform requirements are committed in the repository:

- Android manifest permissions and media service declarations
- iOS `UIBackgroundModes audio` entry and an explicit music audio-session configuration

## Verification

Focused widget regression suite:

```sh
flutter test test/widget_test.dart
```

Full test suite:

```sh
flutter test
```

## Troubleshooting

**Lock screen or Android media notification does not appear**

- Confirm the app is playing a track that has a valid local file path.
- Verify `flutter pub get` has installed `just_audio_background`.
- On iOS, verify the app has been launched from a build that includes `UIBackgroundModes audio` support.

**Downloaded tracks disappear**

- Monolith stores downloaded-track metadata in a manifest under the app documents directory.
- Missing files are automatically pruned from the manifest during load.

**Android build behaves inconsistently after dependency changes**

- Re-run `flutter pub get`.
- Check the vendored plugin overrides in `third_party/`.
