# Development Guide

> **Flutter SDK** `^3.10.1` · **Dart** `^3.5` · **AGP** `8.9.1` · **Kotlin** `2.2.20`

![Development workflow](assets/development-workflow.svg)

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Initial Setup](#initial-setup)
3. [Daily Commands](#daily-commands)
4. [Build Targets](#build-targets)
5. [Project-Specific Notes](#project-specific-notes)
6. [Validation Workflow](#validation-workflow)
7. [Gradle Performance](#gradle-performance)
8. [iOS on Windows](#ios-on-windows)
9. [Key Files](#key-files)
10. [Troubleshooting](#troubleshooting)

---

## Prerequisites

| Tool | Minimum | Notes |
|---|---|---|
| Flutter SDK | `3.10.1` | Stable channel recommended |
| Dart SDK | `3.5` | Bundled with Flutter |
| Android SDK | API 24+ target, API 36 compile | SDK Manager → install platform tools |
| Android NDK | `28.2.13676358` | SDK Manager → NDK (Side by side) |
| JDK | 17 | `JAVA_HOME` must point to JDK 17 |
| Emulator / Device | API 24+, x86_64 image for emulator | Google Play image preferred |
| macOS + Xcode | 15+ | iOS builds only — not possible on Windows |
| CocoaPods | latest | iOS dependency resolution |

### Verify your environment

```sh
flutter doctor -v
```

All items under **Android toolchain** and **Flutter** must show ✓ before building.

---

## Initial Setup

```sh
# 1. Clone and enter the project
git clone https://github.com/naveed-gung/Monolith.git
cd Monolith

# 2. Fetch Dart dependencies
flutter pub get

# 3. (First run only) — pre-warm the Gradle daemon
# This avoids a long wait on the first `flutter run`
cd android && ./gradlew dependencies --no-daemon && cd ..
```

> **After switching branches** always re-run `flutter pub get` before building.  
> Plugin changes in `pubspec.yaml` require a fresh `flutter build` to regenerate native bindings.

---

## Daily Commands

### Run

```sh
# Run on a connected device or emulator
flutter run

# Target a specific device (list with `flutter devices`)
flutter run -d emulator-5554

# Run in release profile (faster, no hot reload)
flutter run --profile
```

### Analyse

```sh
# Static analysis — must pass before every commit
flutter analyze

# Dart formatter check
dart format --output=none --set-exit-if-changed lib/
```

### Test

```sh
# Focused regression suite — widget tests only (fastest feedback loop)
flutter test test/widget_test.dart

# Full test suite
flutter test

# With coverage
flutter test --coverage
```

### Hot reload vs hot restart

| Shortcut | What it does |
|---|---|
| `r` | Hot reload — applies Dart code changes, preserves state |
| `R` | Hot restart — full restart, resets state |
| `q` | Quit runner |

---

## Build Targets

### Android

```sh
# Debug APK (includes all x86_64 ABIs for emulator)
flutter build apk --debug

# Release APK (arm64-v8a only, R8 minification enabled)
flutter build apk --release

# Split APKs per ABI (smallest per-device size)
flutter build apk --split-per-abi --release

# App Bundle (required for Play Store)
flutter build appbundle --release
```

### iOS (macOS only)

```sh
# Debug build
flutter build ios --debug --no-codesign

# Release build (requires valid provisioning profile)
flutter build ios --release
```

### Cleaning up

```sh
# Remove build artefacts (fix most mysterious build failures)
flutter clean && flutter pub get
```

---

## Project-Specific Notes

### Vendored Android plugins (`third_party/`)

Two Android plugins are overridden with local patched copies:

| Package | Why patched |
|---|---|
| `file_selector_android` | AGP / Kotlin version alignment |
| `on_audio_query_android` | Permission-flow stability fix for API 33+ |

**Do not remove these overrides** from `pubspec.yaml` without reviewing the upstream diff. They exist because the upstream versions produce build errors or runtime permission crashes on the current toolchain.

```yaml
# pubspec.yaml — dependency_overrides
dependency_overrides:
  file_selector_android:
    path: third_party/file_selector_android
  on_audio_query_android:
    path: third_party/on_audio_query_android
```

### Android NDK version

`android/app/build.gradle.kts` pins `ndkVersion = "28.2.13676358"`. Both NDK 27 and 28 are typically installed via Android Studio; the pin ensures reproducible native compilation regardless of which NDK Android Studio considers the default.

### Local Maven repositories

`android/build.gradle.kts` adds two offline repositories before the network ones:

```
third_party/android-maven       — patched plugin artifacts
third_party/flutter-engine-maven — Flutter engine AAR for offline builds
```

This allows a full cold build without downloading the Flutter engine from the internet (useful on slow or metered connections).

### User-preference persistence

All user preferences are written to `SharedPreferences` on every setter call and loaded on first boot. See [`architecture.md`](architecture.md#state-ownership) for the full key table. There is no separate migration step — missing keys fall back to defaults.

### Wi-Fi only downloads

When `downloadsOnWifi` is `true` (the default), `MonolithController.startAudioDownload()` calls `Connectivity().checkConnectivity()` before every download. A download on a cellular or unknown connection throws a `StateError` with a user-visible message. Disabling the toggle bypasses this check entirely.

---

## Validation Workflow

Recommended sequence after any code change:

```
1. flutter pub get          ← if pubspec.yaml changed
2. flutter test test/widget_test.dart
3. flutter analyze
4. flutter run              ← manual smoke test on device / emulator
5. flutter build apk        ← only if Android platform files changed
```

For changes that touch `just_audio_background`, `audio_session`, or `Info.plist`, add a final device check on a real device (emulators do not forward audio session signals to the lock screen).

---

## Gradle Performance

The project is tuned for fast incremental builds. Key settings in `android/gradle.properties`:

| Setting | Value | Effect |
|---|---|---|
| `org.gradle.parallel` | `true` | Sub-projects compile in parallel |
| `org.gradle.caching` | `true` | Reuse outputs from prior runs |
| `org.gradle.configuration-cache` | `true` | Skip task-graph recalculation when inputs unchanged |
| `android.nonTransitiveRClass` | `true` | Each module sees only its own R symbols |
| `android.enableJetifier` | `false` | Skip Jetifier (all deps are native AndroidX) |

### First build after adding a new plugin

The first build after `flutter pub add <package>` is always slower because Gradle must download and compile the new package's native Java/Kotlin code. This is a one-time cost per package — subsequent builds use the Gradle build cache.

If a build seems stuck at "Running Gradle task 'assembleDebug'…":

```sh
# Check Gradle daemon status
cd android && ./gradlew --status

# Force a clean daemon start
./gradlew --stop && flutter clean && flutter pub get && flutter run
```

### Increase Gradle heap (if needed)

If your machine has more than 8 GB RAM and you see Gradle OOM errors, increase the heap in `gradle.properties`:

```properties
org.gradle.jvmargs=-Xmx6G -XX:MaxMetaspaceSize=1G -XX:ReservedCodeCacheSize=512m
```

---

## iOS on Windows

You can develop and validate shared Flutter UI from Windows. You cannot produce an iOS build artifact without macOS. The split is:

| Task | Windows | macOS |
|---|---|---|
| Dart / widget development | ✓ | ✓ |
| `flutter analyze` | ✓ | ✓ |
| `flutter test` | ✓ | ✓ |
| Android build and run | ✓ | ✓ |
| iOS simulator | ✗ | ✓ |
| iOS device build | ✗ | ✓ |
| Signing and distribution | ✗ | ✓ |

The GitHub Actions workflow at `.github/workflows/ios.yml` is `workflow_dispatch` only (manual trigger). It produces an unsigned IPA artifact that can be sideloaded with a signing tool on the device side.

---

## Key Files

| File | Purpose |
|---|---|
| `lib/src/app/state/app_controller.dart` | All state, business logic, and service orchestration |
| `lib/src/app/theme/design_tokens.dart` | Visual system — every colour, spacing, motion constant |
| `lib/src/features/shell/presentation/music_shell.dart` | Root scaffold, custom nav bar, mini-player |
| `lib/src/features/player/presentation/player_page.dart` | Full-screen playback UI with bass-reactive glow |
| `lib/src/features/downloads/presentation/downloads_page.dart` | Downloader + offline library |
| `lib/src/core/services/download_store.dart` | Download persistence and artefact lifecycle |
| `lib/src/core/services/local_media_service.dart` | Device library query integration |
| `android/app/build.gradle.kts` | Android module build config (NDK, min/target SDK, ABI filters) |
| `android/gradle.properties` | Gradle performance tuning |
| `ios/Runner/Info.plist` | iOS entitlements (background audio, music library access) |

---

## Troubleshooting

### `flutter run` hangs at "Running Gradle task 'assembleDebug'…"

Most likely causes, in order:

1. **First build after `flutter pub add`** — wait it out once; all subsequent builds use the cache.
2. **Gradle daemon not running** — run `cd android && ./gradlew --stop && cd ..`, then retry.
3. **Bad NDK installation** — open Android Studio → SDK Manager → NDK (Side by side) → install `28.2.13676358`.
4. **Proxy / firewall block** — if behind a corporate proxy, configure `gradle.properties` with proxy settings.

### Widget tests hang or fail unexpectedly

- Use controller injection (`MonolithController(...)`) rather than relying on the production bootstrap.
- Call `await tester.pumpAndSettle()` after any async state change.
- Avoid fake file paths that cause `just_audio` to attempt real playback.

### Android build fails after plugin change

1. Confirm `dependency_overrides` are still present in `pubspec.yaml`.
2. Run `flutter clean && flutter pub get`.
3. Check whether a transitive dependency pulled a newer AGP or Kotlin version.

### Media import crashes after granting permission (Android)

The vendored `third_party/on_audio_query_android` carries a stability fix for the API 33+ permission flow. If you see a crash after the permission grant dialog, verify the override is still active before updating the package.

### Audio plays but no lock-screen / notification

1. Confirm the track has a valid `filePath` — background integration requires a real file URI.
2. Rebuild after any `AndroidManifest.xml` or `Info.plist` change.
3. On iOS, test on a physical device — simulators do not forward all media-session signals.

### Normalize audio has no audible effect

`normalizeAudio` sets `AudioPlayer.volume` to `0.84` (≈ −1.5 dB), which is a mild reduction to prevent distortion on hot masters. It is not loudness normalisation. True LUFS-based normalisation would require an equaliser plugin; this is a known simplification.
