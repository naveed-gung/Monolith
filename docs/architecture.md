# Architecture

> **Platform** Android · iOS &nbsp;|&nbsp; **Language** Dart / Flutter &nbsp;|&nbsp; **State** Single-controller ChangeNotifier

![Architecture map](assets/architecture-map.svg)

---

## Table of Contents

1. [Design Philosophy](#design-philosophy)
2. [Directory Map](#directory-map)
3. [Layer Responsibilities](#layer-responsibilities)
4. [State Ownership](#state-ownership)
5. [Data Flows](#data-flows)
6. [Persistence](#persistence)
7. [Platform Integration](#platform-integration)
8. [Dependency Graph (key)](#dependency-graph-key)
9. [Known Trade-offs](#known-trade-offs)
10. [Extension Points](#extension-points)

---

## Design Philosophy

Monolith is built around a single rule: **one controller owns all mutable state; widgets only read and call**.

This means:

- Every screen derives its render from `MonolithController` properties via `AppScope.watch(context)`.
- No widget holds playback, queue, or download state locally.
- Side effects (play, download, import, preference write) are method calls on the controller — never direct field mutations in widgets.

The consequence is predictable: you can trace any UI behaviour to one file (`app_controller.dart`) without hunting through widget trees.

---

## Directory Map

```
lib/
└── src/
    ├── app/
    │   ├── monolith_app.dart          # MaterialApp wiring, theme + accent injection
    │   ├── state/
    │   │   ├── app_controller.dart    # ★ ALL mutable state lives here
    │   │   └── app_scope.dart         # InheritedWidget accessor (.watch / .read)
    │   └── theme/
    │       ├── design_tokens.dart     # Colors, spacing, radii, motion, typography
    │       └── monolith_theme.dart    # ThemeData builder — light(accent) / dark(accent)
    ├── core/
    │   ├── data/
    │   │   └── demo_catalog.dart      # Fallback tracks for first-launch / no library
    │   ├── models/
    │   │   └── music_models.dart      # Track, enums (AppTab, ThemePreference, …)
    │   ├── services/
    │   │   ├── download_store.dart    # JSON manifest + file I/O for offline audio
    │   │   ├── local_media_service.dart # on_audio_query wrapper
    │   │   ├── manual_audio_import_service.dart # file_selector flow
    │   │   ├── media_downloader.dart  # yt-dlp bridge
    │   │   └── media_downloader_models.dart
    │   └── widgets/
    │       ├── app_card.dart          # Solid-surface content card (no blur)
    │       ├── app_header.dart        # Top bar with logo and settings button
    │       ├── app_icons.dart         # Centralised Phosphor icon registry
    │       ├── atmosphere.dart        # Ambient background gradient + glow orbs
    │       ├── glass_panel.dart       # Frosted glass (mini-player, overlay only)
    │       ├── section_header.dart    # Titled row with optional action link
    │       └── track_artwork.dart     # File → QueryArtwork → URL → fallback painter
    └── features/
        ├── shell/presentation/music_shell.dart    # Root scaffold, nav, mini-player
        ├── library/presentation/library_page.dart
        ├── player/presentation/player_page.dart
        ├── downloads/presentation/downloads_page.dart
        ├── search/presentation/search_page.dart
        └── settings/presentation/settings_page.dart
```

---

## Layer Responsibilities

| Layer | What it owns | What it must not do |
|---|---|---|
| **App** | App lifecycle, theme selection, controller scoping | Business logic |
| **Design Tokens** | Every colour, spacing, radius, curve, and duration | Hard-coded values in widgets |
| **Controller** | All state mutations, service calls, stream subscriptions | Rendering |
| **Core Widgets** | Reusable UI primitives | Feature-specific state |
| **Feature Screens** | Layout, composition, user event wiring | State mutation (call controller methods only) |
| **Services** | Platform I/O, file system, downloader process | UI concerns |

---

## State Ownership

`MonolithController` (a `ChangeNotifier`) is the single source of truth. Its surface area:

### Playback
| Property | Type | Description |
|---|---|---|
| `currentTrack` | `Track` | Active track in the queue |
| `isPlaying` | `bool` | AudioPlayer stream-derived |
| `playbackProgress` | `double` | Position / duration, 0.0–1.0 |
| `currentPosition` | `Duration` | Millisecond-accurate position |
| `currentTrackDuration` | `Duration` | Resolved from player or track metadata |
| `repeatMode` | `RepeatMode` | off / all / one |
| `shuffleEnabled` | `bool` | Queue shuffle state |

### Navigation
| Property | Type | Description |
|---|---|---|
| `currentTab` | `AppTab` | library / downloads / search |
| `selectedCategory` | `LibraryCategory` | tracks / artists / albums / playlists |
| `isPlayerOpen` | `bool` | Full-screen player overlay visible |

### Library
| Property | Type | Description |
|---|---|---|
| `tracks` | `List<Track>` | Merged: downloaded + device + demo fallback |
| `offlineTracks` | `List<Track>` | Downloaded + imported only |
| `isLibraryLoading` | `bool` | Permission request / scan in progress |
| `hasLibraryPermission` | `bool` | OS read permission granted |

### Downloads
| Property | Type | Description |
|---|---|---|
| `downloadTasks` | `List<DownloadTaskInfo>` | All active, paused, and recent tasks |
| `isDownloaderReady` | `bool` | yt-dlp binary initialised |

### User Preferences *(persisted to SharedPreferences)*
| Property | Key | Default |
|---|---|---|
| `themePreference` | `pref_theme` | `system` |
| `accentPreset` | `pref_accent` | `coral` |
| `downloadsOnWifi` | `pref_wifi_only` | `true` |
| `normalizeAudio` | `pref_normalize` | `true` |
| `smoothTransitions` | `pref_transitions` | `true` |
| `immersiveCanvas` | `pref_canvas` | `true` |

---

## Data Flows

### 1 · Device Library Import

```
UI (Library / Settings)
  │
  ▼
MonolithController.refreshLibrary()
  │
  ├─► LocalMediaService.loadTracks()
  │     └─ on_audio_query → OS media store
  │         returns: List<SongModel>  →  List<Track>
  │
  ├─► DownloadStore.loadTracks()
  │     returns: persisted downloaded/imported tracks
  │
  └─► _rebuildTracks()
        merges both lists, preserves selected-track index
        notifyListeners() → all widgets rebuild
```

### 2 · Audio Download

```
UI: DownloadsPage.onDownload()
  │
  ▼
MonolithController.startAudioDownload()
  │
  ├─► _checkConnectivity()  ← throws if wifi-only + cellular
  │
  └─► _startManagedDownload()
        │
        ├─ MediaDownloader.download(request)   ← yt-dlp subprocess
        │    emits: onProgress / onState / onError / onLog streams
        │    → controller updates _downloadTasks + notifyListeners()
        │
        └─ on success:
             DownloadStore.saveTracks()
             LocalMediaService.scanMedia()
             _rebuildTracks()
             notifyListeners()
```

### 3 · Playback

```
UI: controller.selectTrack(track, openPlayer: true)
  │
  ▼
_activateTrackIndex(index)
  │
  ├─► notifyListeners()  ← UI renders new track immediately
  │
  └─► _syncSelectedTrack(autoplay: true)
        │
        ├─ _fadeVolume(to: 0)          ← smooth transition out
        ├─ AudioPlayer.setAudioSource( ← tagged with MediaItem
        │    Uri.file(track.filePath),
        │    tag: MediaItem(id, title, artist, …)
        │  )
        ├─ AudioPlayer.play()
        └─ _fadeVolume(to: targetVolume)  ← normalize + fade in
             just_audio_background publishes MediaItem
             → Android notification + iOS lock screen
```

---

## Persistence

### User Preferences

Written on every setter call via `SharedPreferences`. Loaded at bootstrap before `refreshLibrary()` so the first UI frame reflects saved state.

### Downloaded / Imported Tracks

`DownloadStore` manages a JSON manifest file inside the app's private storage:

```
[app documents]/monolith_downloads/
  manifest.json          ← List<Track> as JSON
  <filename>.mp3         ← audio file
  <filename>.jpg         ← artwork (colocated)
```

On load, the store prunes manifest entries whose backing audio files are missing (handles manual deletion, storage clear, etc.).

---

## Platform Integration

### Android

| Requirement | Implementation |
|---|---|
| Background playback | `AudioService` foreground service via `just_audio_background` |
| System media notification | `MediaButtonReceiver` + `AudioServiceActivity` base class |
| Media metadata | `MediaItem` tag on every `setAudioSource` call |
| Library read | `READ_MEDIA_AUDIO` (API 33+) + `READ_EXTERNAL_STORAGE` (≤ API 32) |
| Incoming audio share | `ACTION_VIEW` + `ACTION_SEND` intent-filters on `audio/*` |

### iOS

| Requirement | Implementation |
|---|---|
| Background audio | `UIBackgroundModes: audio` in `Info.plist` |
| Lock screen / Control Center | `audio_session` configured as `.music()` |
| Apple Music import | `NSAppleMusicUsageDescription` usage description |
| Files app import | `file_selector` document picker |

---

## Dependency Graph (key)

```
MonolithApp
  └── AppScope (InheritedWidget)
        └── MonolithController
              ├── AudioPlayer          (just_audio)
              ├── just_audio_background (MediaSession bridge)
              ├── audio_session        (iOS session config)
              ├── DownloadStore        (JSON persistence)
              ├── LocalMediaService    (on_audio_query)
              ├── MediaDownloader      (yt-dlp subprocess)
              ├── ManualAudioImportService (file_selector)
              ├── SharedPreferences    (preference persistence)
              └── Connectivity         (wifi-only enforcement)
```

---

## Known Trade-offs

| Decision | Benefit | Cost |
|---|---|---|
| Single `MonolithController` | Consistent cross-feature behaviour; easy to trace | Large file; playback + downloads + nav in one place |
| `ChangeNotifier` over Riverpod/Bloc | Zero boilerplate, easy testing via injection | Coarse-grained rebuilds if `notifyListeners()` fires frequently |
| `just_audio_background` over raw `audio_service` | Significantly less setup code | Limited custom notification actions; single-player only |
| Vendored Android plugins in `third_party/` | Stable, offline-capable builds | Manual update responsibility |
| Simulated bass visualisation | No extra package, no FFT overhead | Not frequency-accurate; sine-wave approximation only |

---

## Extension Points

| Where to add | What goes there |
|---|---|
| `lib/src/features/` | New user-facing screen (read state via `AppScope`, call controller methods) |
| `lib/src/core/services/` | New platform integration or I/O layer |
| `lib/src/core/models/music_models.dart` | New enums or shared value types |
| `lib/src/core/widgets/` | New reusable UI primitive |
| `lib/src/app/theme/design_tokens.dart` | New spacing, colour, or motion constant |
| `MonolithController` | New state with `_field`, getter, setter + `_prefs?.setX()` persistence |

> **Rule:** Feature widgets must never import from another feature's directory.  
> Cross-feature communication goes through the controller.
