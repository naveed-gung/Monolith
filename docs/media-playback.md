# Media Playback Integration

> **Stack** `just_audio` · `just_audio_background` · `audio_session`  
> **Surfaces** Android notification · iOS lock screen · Control Center · headset buttons

![Media playback pipeline](assets/media-playback-pipeline.svg)

---

## Table of Contents

1. [Goal](#goal)
2. [Package Roles](#package-roles)
3. [Initialisation Order](#initialisation-order)
4. [Track Activation Flow](#track-activation-flow)
5. [MediaItem Metadata](#mediaitem-metadata)
6. [Smooth Transitions](#smooth-transitions)
7. [Volume Normalisation](#volume-normalisation)
8. [Bass Visualisation](#bass-visualisation)
9. [Platform Configuration](#platform-configuration)
10. [System Surface Coverage](#system-surface-coverage)
11. [Current Limitations](#current-limitations)
12. [Debugging Checklist](#debugging-checklist)
13. [Future Enhancements](#future-enhancements)

---

## Goal

When Monolith plays a track, the operating system should know about it. This means:

- A media notification appears on Android with transport controls (play, pause, skip).
- The iOS lock screen and Control Center show the now-playing card with the same controls.
- Headset buttons and Bluetooth remote controls work without the app in the foreground.
- Audio continues playing when the screen locks or the user switches apps.

Everything below describes how these goals are achieved and what can go wrong.

---

## Package Roles

| Package | Responsibility |
|---|---|
| `just_audio` | Audio decoding, playback engine, position / state streams |
| `just_audio_background` | Bridge between `just_audio` and the OS media session (Android `AudioService`, iOS `MPNowPlayingInfoCenter`) |
| `audio_session` | Tells the OS this app is a *music* player, not a podcast or alert sound |
| `connectivity_plus` | Network-type check before Wi-Fi-only downloads |
| `shared_preferences` | Persist user playback preferences across launches |

---

## Initialisation Order

The sequence in `lib/main.dart` is deliberate:

```dart
// 1. Bind Flutter engine
WidgetsFlutterBinding.ensureInitialized();

// 2. Start background media session BEFORE runApp
//    Any audio loaded after this point will be tracked by the OS.
await JustAudioBackground.init(
  androidNotificationChannelId: 'com.example.monolith.channel.audio',
  androidNotificationChannelName: 'Monolith',
  androidNotificationOngoing: true,
);

// 3. Start the app
runApp(const MonolithApp());
```

Inside `MonolithController._bootstrap()`:

```dart
// 4. Load persisted preferences
await _loadPrefs();

// 5. Configure the audio session as a music player
final session = await AudioSession.instance;
await session.configure(AudioSessionConfiguration.music());

// 6. Initialise the yt-dlp downloader subprocess
await _initializeDownloader();

// 7. Scan device library and load downloaded tracks
await refreshLibrary();
```

> **Critical:** Steps 2 and 5 must run before any audio source is loaded.  
> Reversing the order causes unreliable lock-screen behaviour on iOS.

---

## Track Activation Flow

```
selectTrack(track, openPlayer: true)
  │
  ▼
_activateTrackIndex(index)
  │
  ├── Update _selectedTrackIndex
  ├── notifyListeners()   ← UI renders new track info immediately
  │
  └── _syncSelectedTrack(autoplay: true)
        │
        ├── _fadeVolume(to: 0, ms: 220)    ← smooth out if already playing
        │
        ├── AudioPlayer.setAudioSource(
        │     AudioSource.uri(
        │       Uri.file(track.filePath!),
        │       tag: MediaItem(               ← the OS reads this
        │         id:       track.id,
        │         title:    track.title,
        │         artist:   track.artist,
        │         album:    track.album,
        │         genre:    track.genre,
        │         duration: track.duration,
        │         artUri:   Uri.file(artworkPath) | Uri.parse(artworkUrl),
        │       )
        │     )
        │   )
        │
        ├── AudioPlayer.play()
        │
        └── _fadeVolume(to: targetVolume, ms: 220)   ← smooth in
```

The `MediaItem` tag is the payload the OS surfaces read. Getting it right is the entire job.

---

## MediaItem Metadata

Every audio source loaded by `MonolithController` carries a `MediaItem`. The controller resolves artwork in priority order:

```
1. track.artworkFilePath  →  Uri.file(path)     (colocated .jpg from DownloadStore)
2. track.artworkUrl       →  Uri.parse(url)     (remote thumbnail from yt-dlp)
3. null                                          (OS shows a generic music icon)
```

> `QueryArtworkWidget` (used in the Flutter UI for device-library tracks) is a **UI convenience only**.  
> It does not expose a file URI the system media surface can use.  
> Device-library tracks without a resolved file or URL artwork will show no artwork on the lock screen.

---

## Smooth Transitions

When `smoothTransitions` is enabled, `_syncSelectedTrack` ramps the volume instead of cutting abruptly:

```dart
Future<void> _fadeVolume({required double to, int ms = 220}) async {
  if (!_smoothTransitions) {
    await _audioPlayer.setVolume(to);
    return;
  }
  // 12 steps over ms milliseconds — barely perceptible but eliminates hard cuts
  const steps = 12;
  final from = _audioPlayer.volume;
  final diff = (to - from) / steps;
  for (var i = 1; i <= steps; i++) {
    await Future.delayed(Duration(milliseconds: ms ~/ steps));
    await _audioPlayer.setVolume((from + diff * i).clamp(0.0, 1.0));
  }
}
```

The fade duration (220 ms) is short enough to feel instantaneous but long enough to eliminate the audible click that occurs when a waveform is cut at a non-zero sample value.

---

## Volume Normalisation

When `normalizeAudio` is enabled, `AudioPlayer.setVolume()` is called with `0.84` (≈ −1.5 dB) instead of `1.0`. This is applied:

- On every track activation via `_syncSelectedTrack`.
- Immediately when the toggle is changed via `setNormalizeAudio()`.

### What this is

A mild headroom reduction that makes loud ("hot") masters less likely to clip through the device's output stage. It is not loudness normalisation in the LUFS/R128 sense — true dynamic normalisation requires per-track loudness metadata or a real-time DSP pipeline.

### What this is not

An equaliser, compressor, or limiter. The perceived loudness difference between tracks with different production values will still be audible; this just prevents the loudest tracks from hitting a hard ceiling.

---

## Bass Visualisation

The player UI reacts to playback with a **simulated bass glow** on the album artwork. This is a visual effect, not a real frequency analyser.

### Implementation

The `_visualizerController` (`AnimationController`, period: 1300 ms) drives the effect via a multi-harmonic sine expression evaluated per frame:

```dart
final t = animation.value;   // 0.0 → 1.0, cycling at ~0.77 Hz
final bass = ((
  math.sin(t * math.pi * 2) *
  math.sin(t * math.pi * 3.1) * 0.6 +
  math.sin(t * math.pi * 5.7).abs() * 0.4
).abs()).clamp(0.0, 1.0);
```

The three overlapping sine waves at different frequencies create an interference pattern that resembles a beat envelope without being perfectly regular.

`bass` then controls:

| Property | Idle | Peak |
|---|---|---|
| Glow blur radius | 28 px | 80 px |
| Glow spread radius | 0 px | 6 px |
| Glow opacity | 0.18 | 0.54 |
| Artwork scale | 0.97× | 1.02× |

The colour of the glow is always `scheme.primary` — the user's selected accent colour. Changing the accent in Settings immediately changes the glow colour.

### Why not real FFT?

Real-time frequency analysis on Flutter requires a native audio tap, which `just_audio` does not expose without a platform channel. Adding `audio_waveforms` or a custom platform plugin is a viable future enhancement but was excluded to keep the dependency surface small.

---

## Platform Configuration

### Android

```xml
<!-- AndroidManifest.xml -->

<!-- Background playback service -->
<service
  android:name="com.ryanheise.audioservice.AudioService"
  android:foregroundServiceType="mediaPlayback"
  android:exported="true">
  <intent-filter>
    <action android:name="android.media.browse.MediaBrowserService" />
  </intent-filter>
</service>

<!-- Hardware media button receiver -->
<receiver
  android:name="com.ryanheise.audioservice.MediaButtonReceiver"
  android:exported="true">
  <intent-filter>
    <action android:name="android.intent.action.MEDIA_BUTTON" />
  </intent-filter>
</receiver>

<!-- Accept audio files shared from other apps -->
<intent-filter>
  <action android:name="android.intent.action.VIEW"/>
  <category android:name="android.intent.category.DEFAULT"/>
  <data android:mimeType="audio/*"/>
</intent-filter>
<intent-filter>
  <action android:name="android.intent.action.SEND"/>
  <category android:name="android.intent.category.DEFAULT"/>
  <data android:mimeType="audio/*"/>
</intent-filter>
```

Required permissions:

```xml
<uses-permission android:name="android.permission.WAKE_LOCK" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
<uses-permission android:name="android.permission.READ_MEDIA_AUDIO" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />
```

### iOS

```xml
<!-- Info.plist -->
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>

<key>NSAppleMusicUsageDescription</key>
<string>Monolith needs access to your media library to import songs from your device.</string>
```

The `audio_session` call in `_configureAudioSession()` also sets the session category on iOS so the app behaves correctly when another app takes audio focus (phone call, Siri, etc.).

---

## System Surface Coverage

| Surface | Android | iOS |
|---|---|---|
| Lock screen metadata (title, artist) | ✓ | ✓ |
| Lock screen artwork | ✓ file/URL art | ✓ file/URL art |
| Transport controls (play/pause/skip) | ✓ | ✓ |
| Notification shade player | ✓ | — (not a thing on iOS) |
| Control Center now-playing | — | ✓ |
| Headset button / BT remote | ✓ | ✓ |
| Car / Android Auto | ✓ via MediaBrowser | — |
| Siri integration | — | Partial via MPRemoteCommandCenter |

---

## Current Limitations

| Limitation | Impact | Workaround |
|---|---|---|
| `QueryArtworkWidget` art not exposed to OS | Device-library tracks may show no artwork on lock screen | Export artwork to a file path and use `artworkFilePath` |
| Single `AudioPlayer` instance | Cannot cross-fade or play two sources simultaneously | Not required for current use case |
| No real-time EQ / DSP | `normalizeAudio` is a volume reduction, not true loudness normalisation | Future: `just_audio_equalizer` (Android only) |
| Bass visualiser is simulated | Glow does not react to actual frequency content | Future: platform channel for audio tap |
| iOS build requires macOS | Cannot validate iOS media session from Windows | Use GitHub Actions workflow or a macOS machine |

---

## Debugging Checklist

### Lock screen / notification not appearing

```
□ Track has a valid local filePath (not null, not an empty string)
□ Track was loaded through MonolithController.selectTrack()
□ JustAudioBackground.init() ran before runApp()
□ audio_session configured AudioSessionConfiguration.music() before first play
□ AndroidManifest.xml includes AudioService, FOREGROUND_SERVICE, WAKE_LOCK
□ App was rebuilt after any manifest change
□ On iOS: testing on a physical device, not a simulator
```

### Artwork missing on lock screen

```
□ track.artworkFilePath points to a real, existing file
□ track.artworkUrl is a valid, accessible URI
□ Not relying on QueryArtworkWidget — it does not produce a system-usable URI
□ On Android: FOREGROUND_SERVICE_MEDIA_PLAYBACK declared in manifest
```

### Audio cuts out when screen locks (iOS)

```
□ UIBackgroundModes contains "audio" in Info.plist
□ audio_session configured before first play
□ App was rebuilt from the updated Info.plist (not just hot-reloaded)
```

### Headset buttons not responding

```
□ MediaButtonReceiver declared in AndroidManifest.xml (Android)
□ AudioService is exported (Android)
□ App has been foregrounded at least once since install (iOS activation requirement)
```

---

## Future Enhancements

| Enhancement | Complexity | Dependency |
|---|---|---|
| Real-time bass visualisation via FFT | High | Platform channel + audio tap API |
| True per-track loudness normalisation | Medium | `just_audio_equalizer` (Android) + iOS DSP |
| Custom notification actions (heart, add-to-playlist) | Medium | Direct `audio_service` integration |
| Richer queue metadata in lock screen | Low | Extend `MediaItem` tag in `_syncSelectedTrack` |
| Artwork caching for device-library tracks | Low | Copy artwork to `DownloadStore` directory on first play |
| Android Auto / Automotive OS support | High | `MediaBrowserServiceCompat` implementation |
| AirPlay / Cast support | High | `just_audio` cast plugin (experimental) |
