# Architecture

## Overview

Monolith is organized as a Flutter application with a controller-centered state model and feature-scoped presentation code. The architecture favors a single source of truth for playback, downloads, playlists, and navigation so Android and iOS can share the same UI behavior.

![Architecture map](assets/architecture-map.svg)

The diagram above shows the intended layering: startup and theming at the top, controller state in the middle, shared services on the side, and feature widgets at the presentation edge.

## Top-Level Structure

### `lib/main.dart`

Application entry point.

- ensures Flutter bindings are initialized
- initializes `just_audio_background`
- starts the app with `MonolithApp`

### `lib/src/app/`

Application composition and global concerns.

- `monolith_app.dart`: creates and scopes the controller
- `state/app_controller.dart`: central application state and orchestration
- `state/app_scope.dart`: inherited access to the controller
- `theme/`: light and dark theme definitions

### `lib/src/core/`

Reusable, non-feature-specific code.

- `models/`: `Track`, download models, enums, and shared value types
- `services/`: local media access, download persistence, manual imports, downloader integration
- `widgets/`: shared widgets such as artwork rendering
- `data/`: demo and fallback data

### `lib/src/features/`

Presentation split by user-facing area.

- `shell/`: root scaffold, navigation, mini-player, and player overlay
- `library/`: track, playlist, artist, and album browsing surfaces
- `downloads/`: downloader form, activity state, offline track listing, filtering, and sorting
- `player/`: full-screen now-playing experience
- `search/`: search flow and track launch entry points
- `settings/`: app preferences and toggles

## State Ownership

`MonolithController` is the primary orchestration layer. It owns:

- active tab selection
- library category selection
- playback position, duration, and repeat state
- current track and queue navigation
- playlist membership and creation
- download tasks and downloader event subscriptions
- imported and downloaded track persistence
- theme mode

This keeps feature widgets mostly declarative and reduces duplicated playback logic between the shell, library, downloads, and player views.

## Data Flow

### Local Library Import

1. UI triggers a refresh or import action.
2. `LocalMediaService` requests permission and queries songs through `on_audio_query`.
3. Song models are mapped into shared `Track` objects.
4. `MonolithController` rebuilds the app-level track list and keeps the selected item stable when possible.

### Downloaded Audio

1. User submits a supported media URL.
2. The downloader service resolves metadata and starts the download.
3. `MonolithController` listens to progress, state, error, and log streams.
4. Completed downloads are persisted through `DownloadStore`.
5. Downloaded entries are merged into the app track list.

### Playback

1. User selects a playable track.
2. `MonolithController` loads a tagged audio source into `AudioPlayer`.
3. The media tag is exposed to `just_audio_background` as a `MediaItem`.
4. Player streams update UI state for progress, duration, and playback state.
5. System surfaces consume the same metadata for lock-screen and notification controls.

## Persistence

Downloaded and imported audio metadata is stored through `DownloadStore`, which:

- creates app-managed download and import directories
- stores a manifest JSON file
- resolves artwork files colocated with audio files
- prunes manifest entries whose backing files are missing

## Platform Integration

### Android

- media-library permissions are declared in the manifest
- background playback support is exposed through `AudioService`
- notification controls are driven by `just_audio_background`

### iOS

- library import uses the Apple media library path where supported
- background audio capability is declared through `UIBackgroundModes`
- `audio_session` configures the app as a music playback session
- lock-screen now-playing metadata is supplied through the tagged media item

## Tradeoffs

- A single controller keeps behavior consistent, but it also means playback, downloads, and navigation are tightly coordinated in one file.
- `just_audio_background` is a good fit for the current single-player design. If Monolith grows into multiple coordinated players or richer custom media actions, moving to direct `audio_service` usage would provide more control.

## Where To Extend

- New feature surfaces should stay inside `lib/src/features/` and read state through `AppScope`.
- New persistence or integration logic should live under `lib/src/core/services/`.
- Cross-feature models and enums should remain in `lib/src/core/models/`.
