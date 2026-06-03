# Monolith — Work Order & Diagnosis → release **1.0.3**

> Target device: **iPhone X, iOS 16.7.16, sideloaded.** Flutter, single `MonolithController` (`ChangeNotifier`), `just_audio` stack.
> Hand this straight to Claude Code. Each section: **Diagnosis → Root cause → Exact change → Code.**
> This revision: item 6 now covers **Android + iOS**, adds the **iOS "won't play until app restart" bug**, the **1.0.3 release + Android rebuild** steps, and **4 new features**.

---

## TL;DR priority order

1. **iOS playback bug (NEW, §0)** — downloaded song won't play until you kill+reopen the app. One missing line. Fix first; it's the most user-breaking.
2. **Heat/battery (§1 + §2)** — mostly ONE bug: a post-frame callback scheduled every rebuild while the controller rebuilds the tree several times/sec during playback.
3. Items 3 & 4 — "agent said it did it but it isn't there." Both real gaps.
4. Item 5 — haptics (quick win).
5. Item 6 — icons, now Android + iOS.
6. New features (§7): smart playlists, lyrics, equalizer (Android), real FFT visualizer.
7. **Ship as 1.0.3** (§8): bump version, rebuild Android APK on computer, update CHANGELOG, surface version in Settings, attach new icon, re-release.

---

## 0. NEW BUG — iPhone: a freshly downloaded song won't play until the app is cleared and reopened

### 0.1 Symptom
On iOS, after a download finishes you tap play and nothing happens. Force-quit the app, reopen it, and the same song now plays. (The agent claimed a fix; it didn't work.)

### 0.2 Root cause — the new track is *selected* but its audio source is never *loaded*

In `lib/src/app/state/app_controller.dart`, the download-completion handler ends like this:

```dart
_downloadedTracks = [track, ..._downloadedTracks.where((e) => e.filePath != track.filePath)];
_fatalDownloadErrors.remove(task.processId);
await _downloadStore.saveTracks(_downloadedTracks);
await _localMediaService.scanMedia(result.outputPath!);

_rebuildTracks(preferredTrackId: track.id);     // ← selects the new track
_upsertDownloadTask(/* mark completed */);
notifyListeners();                                // ← UI updates, but…
```

`_rebuildTracks(preferredTrackId: track.id)` changes `_selectedTrackIndex` to the new track, but it **never calls `_syncSelectedTrack()`**, which is the method that actually does `_audioPlayer.setAudioSource(Uri.file(track.filePath!), tag: …)`. So:

- The player engine still has the *old* source (or none) loaded.
- `togglePlayback()` only calls `_audioPlayer.play()` — it does **not** load a source. So tapping play plays nothing.

Now compare cold start: `_bootstrap()` → `refreshLibrary()` → `_rebuildTracks(...)` **followed by `await _syncSelectedTrack(autoplay: false)`**. That second call loads the source. That's precisely why killing + reopening the app makes the song playable. The download path is missing that exact line.

### 0.3 Why the agent's earlier "fix" didn't fix this
The 1.0.2 change added `audio_session` config at startup, which fixed a *different* iOS symptom (a track reporting `00:00 / 00:00` and being silent). That's a session-category bug. Your bug is a missing source-load after download — same family ("won't play on iOS"), different cause. The session fix can't help when no source was ever set.

### 0.4 Fix — load the source as soon as the download completes

In `_onDownloadComplete` (the success branch), after `_rebuildTracks(preferredTrackId: track.id);` add a source-load. Keep `autoplay: false` so it doesn't start blasting the moment a download finishes — it just makes the track instantly playable:

```dart
_rebuildTracks(preferredTrackId: track.id);

// Load the just-downloaded file into the player engine NOW, so the first tap
// on Play works without a relaunch. Without this the track is selected but no
// AudioSource is set, and togglePlayback() has nothing to play (iOS bug).
await _syncSelectedTrack(autoplay: false);

_upsertDownloadTask(
  _downloadTaskById(task.processId).copyWith(
    status: DownloadTaskStatus.completed,
    progress: 1,
    outputPath: result.outputPath,
    errorMessage: null,
  ),
);
notifyListeners();
```

### 0.5 iOS file-flush hardening (belt and suspenders)
`just_audio` on iOS occasionally throws on the *first* `setAudioSource` for a file written milliseconds earlier (AVPlayer reads before the OS finished flushing). `_syncSelectedTrack` **already has** a `try/catch` with a 500ms delay + one retry — so calling it here gets that protection for free. Confirm that retry block is intact. If you still see intermittent first-play failures, bump the retry delay from 500ms to ~800ms on iOS only.

### 0.6 Verify
1. Cold start, download a song, tap Play immediately → it plays. No relaunch.
2. Download a second song while the first plays → first keeps playing, second becomes playable on tap.
3. Force-quit, reopen → still plays (regression check on the cold-start path).

---

## 1. iPhone X heats up under the camera and ramps 0→100 fast

### 1.1 What's happening
The heat under the rear camera is the **A11 SoC + upper battery cell** — a CPU/GPU pegging problem, not the camera. The phone thermal-throttles and the top of the chassis warms.

### 1.2 Root cause #1 — post-frame callback scheduled every frame (the big one)
In `lib/src/features/shell/presentation/music_shell.dart`, `build()`:

```dart
final controller = AppScope.watch(context);          // rebuilds on EVERY notifyListeners()
final tabIndex = AppTab.values.indexOf(controller.currentTab);
WidgetsBinding.instance.addPostFrameCallback((_) {     // ← scheduled on every rebuild
  final pc = _pageController;
  if (!mounted || pc == null || !pc.hasClients) return;
  if (pc.page?.round() == tabIndex) return;
  if (pc.position.isScrollingNotifier.value) return;
  pc.animateToPage(tabIndex, ...);
});
```

`AppScope.watch` subscribes the shell to the controller. During playback the controller fires `notifyListeners()` from the position stream (throttle only suppresses sub-250ms same-second updates → still ~1–4 notifies/sec, more on transitions). Each notify rebuilds the root shell **and schedules another post-frame callback**. Scheduling a post-frame callback every build keeps the engine doing continuous frame work and denies the A11 idle gaps → sustained high P-state → heat + fast battery drain.

### 1.3 Root cause #2 — mini-player repaints on every position tick
`_MiniPlayer` renders `LinearProgressIndicator(value: controller.playbackProgress)`. Because the whole shell rebuilds on every position notify, that bar (and its neighbours) re-lays-out and repaints several times/sec even with the player sheet closed.

### 1.4 Why *every* sideloaded app warms your phone (not your bug)
- **AltStore/SideStore background refresh + on-device re-signing** wakes the phone on a schedule and burns CPU — an AltStore cost, not Monolith's.
- **No App Store thermal/QA gating** on sideloaded builds.
- Your Flutter release IPA is AOT-compiled, so JIT cost is minimal for Monolith specifically.
- **Use TrollStore Lite** (works on 16.7.x — your README documents it): permanent install, normal entitlements, no AltStore refresh tax.

### 1.5 Fix
**Change A — schedule the post-frame callback only when the tab actually changed.** Add field `int? _lastSyncedTabIndex;` and replace the block:

```dart
final tabIndex = AppTab.values.indexOf(controller.currentTab);
if (tabIndex != _lastSyncedTabIndex) {
  _lastSyncedTabIndex = tabIndex;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final pc = _pageController;
    if (!mounted || pc == null || !pc.hasClients) return;
    if (pc.page?.round() == tabIndex) return;
    if (pc.position.isScrollingNotifier.value) return;
    pc.animateToPage(tabIndex, duration: AppMotion.durMedium, curve: AppMotion.emphasized);
  });
}
```

**Change B — isolate the live position UI so only it repaints.** Expose position/progress as `ValueNotifier`s on the controller and stop firing `notifyListeners()` per tick.

In `MonolithController`:
```dart
final ValueNotifier<double> progress = ValueNotifier<double>(0);
final ValueNotifier<Duration> positionListenable = ValueNotifier<Duration>(Duration.zero);
```
In `_bindAudioPlayer()`'s position listener, drive the notifiers instead of `notifyListeners()`:
```dart
_playerPositionSubscription = _audioPlayer.positionStream.listen((position) {
  _currentPosition = position;
  positionListenable.value = position;
  final total = currentTrackDuration.inMilliseconds;
  progress.value = total == 0 ? 0 : (position.inMilliseconds / total).clamp(0.0, 1.0);
  // NO notifyListeners() here.
});
```
Keep `notifyListeners()` for discrete events (play/pause, track change, completion). Dispose both notifiers in `MonolithController.dispose()`.

Drive the bar + time labels from the notifiers:
```dart
RepaintBoundary(
  child: ValueListenableBuilder<double>(
    valueListenable: controller.progress,
    builder: (_, value, __) => LinearProgressIndicator(
      value: value,
      backgroundColor: scheme.outlineVariant.withValues(alpha: 0.3),
      valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
      minHeight: 3,
    ),
  ),
),
```
Do the same for the elapsed-time label using `positionListenable`.

**Change C — confirm visualizer gating holds.** `_handleControllerChanged` repeats the visualizer only when `isPlaying && isPlayerOpen && immersiveCanvas` (already correct). After Change B verify nothing else calls `.repeat()`.

### 1.6 Verify
```sh
flutter run --profile
```
DevTools → Performance: with a track playing and the sheet closed, UI + Raster threads should be near-flat, not a continuous sawtooth. CPU profiler: `addPostFrameCallback`/`drawFrame` should go quiet between events. Physically: 10 min screen-off playback should leave the phone warm at most.

---

## 2. Battery drain on iPhone X
Same root cause as §1 — sustained CPU prevents SoC sleep, and a hot SoC draws more current for the same work (thermal feedback). Fix §1 and battery improves proportionally. Background audio (`UIBackgroundModes: audio`) is correct and expected — don't disable it. The connectivity stream is low-frequency on iOS — leave it.

---

## 3. First-visit "Import from Apple Music" popup (iOS only)

### 3.1 Status: already exists, gated, probably already "seen"
Implemented in `monolith_app.dart` → `_maybePromptForAppleMusicImport()`: an `AlertDialog` titled "Import from Apple Music?", gated by `supportsAppleMusicImportPrompt` (iOS) and `shouldShowImportPrompt` (`!_hasSeenImportPrompt`), and it persists `pref_seen_import_prompt = true`. You didn't see it because the flag was already set, or your build predated it.

### 3.2 Do this
**(a) Match your exact button labels** ("Import"/"Cancel") in `monolith_app.dart`:
```dart
actions: [
  TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
  FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Import')),
],
```
**(b) Add a re-trigger** in `MonolithController`:
```dart
Future<void> resetImportPrompt() async {
  _hasSeenImportPrompt = false;
  await _prefs?.remove(_kSeenImportPrompt);
  notifyListeners();
}
```
Wire a "Re-run first-time import prompt" action row in Settings → Quick actions. For a fresh test now: reinstall, or call `resetImportPrompt()` once. The dialog only shows on iOS.

---

## 4. "Monolith folder" in Settings like Apple Music — it's missing

### 4.1 Status: half-done
The folder exists on disk (`…/Monolith/Music`, shown in Files as **On My iPhone › Monolith › Music**) and a **Storage page** exists. But Settings has **no storage row and no Apple Music toggle** — sections are Appearance → Playback → Quick actions → Developer. The agent created the folder, then claimed a Settings entry it never added.

### 4.2 Fix — add two Settings rows
**(a) Apple Music import toggle (iOS)** — controller already has the state:
```dart
if (controller.supportsAppleMusicImportPrompt) ...[
  _Divider(),
  _ToggleRow(
    title: 'Apple Music import',
    subtitle: 'Pull songs from your device music library',
    value: controller.isAppleMusicImportEnabled,
    onChanged: (v) => controller.setAppleMusicImportEnabled(v, retryPermissionRequest: true),
  ),
],
```
**(b) "Monolith folder" row** opening the existing StoragePage:
```dart
_SectionLabel(label: 'Storage'),
SliverToBoxAdapter(
  child: Padding(
    padding: const EdgeInsets.fromLTRB(AppSpacing.screenInset, 0, AppSpacing.screenInset, AppSpacing.xxl),
    child: _SettingsGroup(children: [
      _ActionRow(
        icon: AppIcons.folderOpen, // add: static final folderOpen = PhosphorIcons.folderOpen();
        title: 'Monolith folder',
        subtitle: Platform.isIOS ? 'On My iPhone › Monolith › Music' : 'Browse downloaded & imported files',
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StoragePage())),
      ),
    ]),
  ),
),
```
StoragePage reads the path via `AppScope.read(context).getDownloadDirectoryPath()` and AppScope sits above the navigator, so a pushed route works.

### 4.3 Why "like Apple Music"
A sideloaded app won't reliably get its own pane in the iOS *system* Settings app (that needs a `Settings.bundle` + proper signing). "Like Apple Music in Settings" realistically means inside Monolith's own Settings screen — which 4.2 delivers.

---

## 5. Haptic feedback for clicks (no audio, haptic only)

Use Flutter's built-in `HapticFeedback` (no new dependency). iPhone X has a Taptic Engine.

**Service** `lib/src/core/services/haptics_service.dart`:
```dart
import 'package:flutter/services.dart';
enum HapticStrength { selection, light, medium, heavy }
class HapticsService {
  HapticsService({this.enabled = true});
  bool enabled;
  Future<void> tap([HapticStrength s = HapticStrength.light]) async {
    if (!enabled) return;
    switch (s) {
      case HapticStrength.selection: await HapticFeedback.selectionClick();
      case HapticStrength.light:     await HapticFeedback.lightImpact();
      case HapticStrength.medium:    await HapticFeedback.mediumImpact();
      case HapticStrength.heavy:     await HapticFeedback.heavyImpact();
    }
  }
}
```
**Controller wiring + persistence:**
```dart
static const _kHaptics = 'pref_haptics';
bool _hapticsEnabled = true;
bool get hapticsEnabled => _hapticsEnabled;
final HapticsService _haptics = HapticsService();
void setHapticsEnabled(bool value) {
  if (_hapticsEnabled == value) return;
  _hapticsEnabled = value; _haptics.enabled = value;
  _prefs?.setBool(_kHaptics, value); notifyListeners();
}
void hapticTap([HapticStrength s = HapticStrength.light]) => _haptics.tap(s);
```
In `_loadPrefs()`: `_hapticsEnabled = p.getBool(_kHaptics) ?? true; _haptics.enabled = _hapticsEnabled;`

**Fire on interactions only (not audio callbacks):** play/pause → `medium`; next/prev → `light`; tab change → `selection`; toggles & accent swatch → `selection`; open/close player → `light`; delete confirm → `heavy`. Example:
```dart
onPressed: track.canPlay
  ? () { controller.hapticTap(HapticStrength.medium); controller.togglePlayback(); }
  : null,
```
**Settings toggle** in Playback section:
```dart
_Divider(),
_ToggleRow(title: 'Haptic feedback', subtitle: 'Vibrate on taps and controls',
  value: controller.hapticsEnabled, onChanged: controller.setHapticsEnabled),
```
iOS gotcha: no entitlement needed even sideloaded. Prefer `selectionClick()` for high-frequency taps (crispest, least "mushy").

---

## 6. App icons matching each accent + in-app "m" logo auto-changing — **Android AND iOS**

Two separate things: **(A)** the in-app "m" logo color (easy, auto-follows accent on both platforms) and **(B)** the home-screen launcher icon swapping (alternate icons — done for both Android and iOS).

### 6.1 Part A — in-app "m" logo auto-matches the accent (both platforms, do now)
The logo lives in `app_header.dart`. Make its color `Theme.of(context).colorScheme.primary` (which **is** the selected accent — `MonolithTheme` sets `primary: accent.base`). It then auto-updates the instant the user picks a swatch, identically on Android and iOS:
```dart
Text('m', style: TextStyle(
  fontFamily: 'Georgia', fontWeight: FontWeight.bold,
  color: Theme.of(context).colorScheme.primary, // auto-follows accent
));
```
If it's an SVG asset, tint with `ColorFiltered`/paint using the accent. No new assets needed.

### 6.2 Part B — generate one launcher icon per accent (shared PNGs for both platforms)
Generalize `branding/gen_icon.py` to emit one icon per accent using the exact swatch colors from `design_tokens.dart`. These PNGs feed **both** the Android adaptive icon and the iOS alternate icons:
```python
ACCENTS = [
    ("coral",   (0xFF,0x4D,0x5E), (0xC2,0x3A,0x48)),
    ("violet",  (0x8B,0x5C,0xF6), (0x6D,0x42,0xC8)),
    ("ocean",   (0x1F,0xC8,0xC0), (0x12,0x8F,0x8A)),
    ("lime",    (0x38,0xD6,0x6B), (0x23,0xA3,0x4E)),
    ("amber",   (0xFF,0xB0,0x20), (0xCB,0x88,0x12)),
    ("magenta", (0xFF,0x3D,0x9A), (0xC8,0x2A,0x76)),
]
for name, c1, c2 in ACCENTS:
    src = diagonal_gradient(S, c1, c2)              # refactor lerp/gradient to take c1,c2
    draw_m(src, target_w=int(S*0.56), fill=(255,255,255))
    src.save(os.path.join(HERE, f"app_icon_{name}.png"))
    fg = Image.new("RGBA",(S,S),(0,0,0,0))
    draw_m(fg, target_w=int(S*0.46), fill=(255,255,255,255))
    fg.save(os.path.join(HERE, f"app_icon_{name}_fg.png"))
```
Keep the "m" white on all six gradients for consistency (it reads fine on every accent).

### 6.3 Part B — make the home-screen icon swappable on **both** platforms
Use **`flutter_dynamic_icon_plus`** — it supports Android *and* iOS alternate icons from one Dart API. Add to `pubspec.yaml` dependencies:
```yaml
flutter_dynamic_icon_plus: ^<latest>
```

**iOS setup** — alternate icons must be baked into the bundle. Add each accent's PNG set (60pt @2x/@3x → 120×120, 180×180) to `ios/Runner` and declare in `Info.plist`:
```xml
<key>CFBundleIcons</key>
<dict>
  <key>CFBundlePrimaryIcon</key>
  <dict><key>CFBundleIconFiles</key><array><string>AppIcon</string></array></dict>
  <key>CFBundleAlternateIcons</key>
  <dict>
    <key>icon_violet</key>
    <dict><key>CFBundleIconFiles</key><array><string>icon_violet</string></array><key>UIPrerenderedIcon</key><false/></dict>
    <!-- repeat: icon_ocean, icon_lime, icon_amber, icon_magenta -->
  </dict>
</dict>
```

**Android setup** — alternate icons map to `activity-alias` entries in `AndroidManifest.xml`, one per accent, each pointing at a different `android:icon`/`android:roundIcon`. Generate the per-accent mipmaps (the package's docs show the exact alias block). Example alias:
```xml
<activity-alias
  android:name=".MainActivityViolet"
  android:enabled="false"
  android:exported="true"
  android:icon="@mipmap/ic_launcher_violet"
  android:roundIcon="@mipmap/ic_launcher_violet_round"
  android:targetActivity=".MainActivity">
  <intent-filter>
    <action android:name="android.intent.action.MAIN"/>
    <category android:name="android.intent.category.LAUNCHER"/>
  </intent-filter>
</activity-alias>
<!-- repeat for ocean, lime, amber, magenta; coral = the default MainActivity icon -->
```

**Swap logic (shared, both platforms)** — add an explicit picker, don't auto-swap on every accent tap (see 6.4). A dedicated method:
```dart
import 'package:flutter_dynamic_icon_plus/flutter_dynamic_icon_plus.dart';

Future<void> setLauncherIcon(AccentPreset preset) async {
  try {
    final supported = await FlutterDynamicIconPlus.supportsAlternateIcons;
    if (!supported) return;
    // coral is the primary icon (null); others are named alternates.
    final name = preset == AccentPreset.coral ? null : 'icon_${preset.name}';
    await FlutterDynamicIconPlus.setAlternateIconName(iconName: name);
  } catch (_) {/* non-fatal */}
}
```

### 6.4 Hard truths (read before wiring)
- **iOS shows a system alert** ("You have changed the icon for Monolith") on every `setAlternateIconName` call, and you cannot suppress it on iOS 16 without private API. **So do NOT auto-swap the home icon on every accent tap** — it would spam the alert. Android has no such alert but a flicker/relaunch of the launcher entry.
- **Alternate icons are bundle-baked**, not runtime-generated. The §6.2 PNGs get compiled into `ios/Runner` and Android `mipmap`s.
- Works the same on a sideloaded/TrollStore build — no extra entitlement.

### 6.5 Recommended final design
- **In-app "m" logo** auto-follows accent (Part A) — ship on both platforms, free, no alerts.
- **Home-screen icon**: add a separate **"App icon"** picker row in Settings (shows the 6 generated icons). Swapping is a deliberate user choice → one acceptable alert on iOS. Do **not** silently tie it to the accent toggle.

---

## 7. New features to add this release

### 7.1 Smart playlists / auto-queue ("recently added", "most played", "never played")

**Data:** add fields to `Track` (in `music_models.dart`) and persist them in the manifest:
```dart
final int playCount;        // default 0
final DateTime? lastPlayed; // null = never played
final DateTime addedAt;     // set when downloaded/imported
```
Update `Track.fromJson`/`toJson`/`copyWith` accordingly (default `playCount: 0`, `lastPlayed: null`, `addedAt: DateTime.now()` on creation). Manifest is just JSON, so this is backward-compatible — missing keys fall back to defaults on load.

**Increment play count** when a track actually starts. In `_syncSelectedTrack` after a successful `play()` (autoplay branch), or better in the player-state listener when state transitions to playing for a new track:
```dart
void _registerPlay(Track track) {
  if (track.source != TrackSource.downloaded && track.source != TrackSource.imported) return;
  final updated = track.copyWith(playCount: track.playCount + 1, lastPlayed: DateTime.now());
  _downloadedTracks = _downloadedTracks.map((t) => t.id == track.id ? updated : t).toList();
  unawaited(_downloadStore.saveTracks(_downloadedTracks));
}
```
(Guard against double-counting on pause/resume: only count when the *track id* changes, not on every play.)

**Smart playlists** are computed getters on the controller — no storage needed:
```dart
List<Track> get recentlyAdded =>
    ([..._downloadedTracks]..sort((a, b) => b.addedAt.compareTo(a.addedAt))).take(50).toList();
List<Track> get mostPlayed =>
    ([..._downloadedTracks]..sort((a, b) => b.playCount.compareTo(a.playCount)))
      .where((t) => t.playCount > 0).toList();
List<Track> get neverPlayed =>
    _downloadedTracks.where((t) => t.playCount == 0).toList();
```
**UI:** add a "Smart" row in the Library category selector (alongside Tracks/Playlists) that lists these three as tappable virtual playlists. Reuse the existing playlist screen — feed it the computed list.

### 7.2 Lyrics view (embedded ID3 `USLT` + `.lrc` sidecar, synced highlighting)

**Source 1 — embedded USLT:** the `id3` package (already a transitive dep) reads ID3v2 frames. Add a small reader in a service:
```dart
// lib/src/core/services/lyrics_service.dart
import 'dart:io';
import 'package:id3/id3.dart';
class LyricsService {
  Future<String?> embeddedLyrics(String filePath) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      final tag = MP3Instance(bytes)..parseTagsSync();
      final m = tag.getMetaTags();
      return (m?['USLT'] ?? m?['Lyrics'])?.toString();
    } catch (_) { return null; }
  }
}
```
(Confirm the exact key the `id3` version exposes for USLT; if it doesn't expose USLT, fall back to source 2.)

**Source 2 — `.lrc` sidecar:** look for `<same-stem>.lrc` next to the audio file in the Monolith folder:
```dart
Future<String?> sidecarLrc(String audioPath) async {
  final lrc = File('${audioPath.substring(0, audioPath.lastIndexOf('.'))}.lrc');
  return await lrc.exists() ? lrc.readAsString() : null;
}
```

**Synced highlighting:** parse `.lrc` timestamps `[mm:ss.xx]` into `(Duration, String)` pairs. In the player, drive the active line from `controller.positionListenable` (the notifier you added in §1.5) — find the last line whose timestamp ≤ current position and highlight it with `scheme.primary`, dim the rest. Plain (unsynced) lyrics just render as scrollable text. Add a "Lyrics" tab/sheet in the player page; show an empty state when neither source exists.

### 7.3 Equalizer (Android-only via `just_audio` EQ; gated per-platform)

**Reality:** `just_audio`'s `AndroidEqualizer` is Android-only; iOS has no public audio tap for EQ. Gate the entire feature behind `Platform.isAndroid`.

Attach the EQ as an `AudioPipeline` when constructing the player (Android only):
```dart
import 'package:just_audio/just_audio.dart';
final AndroidEqualizer _equalizer = AndroidEqualizer();
// player construction (Android branch):
_audioPlayer = AudioPlayer(
  audioPipeline: AudioPipeline(androidAudioEffects: [_equalizer]),
);
```
Expose enable + per-band gain:
```dart
Future<void> setEqEnabled(bool v) async => _equalizer.setEnabled(v);
Future<AndroidEqualizerParameters> eqParams() => _equalizer.parameters;
```
**UI:** a "Sound" section in Settings shown only on Android — an enable toggle plus a slider per band from `parameters.bands` (each band: `centerFrequency`, `setGain(double)`). Pair it visually with the existing "Normalize audio" toggle. Persist enabled-state + per-band gains in `SharedPreferences`. On iOS, render a short "Equalizer is Android-only on this build" note or hide the section entirely.

### 7.4 Real waveform / FFT visualizer (replace the sine-wave fake)

**Current state:** the player glow uses a hand-rolled multi-sine `bass` value — it doesn't react to actual audio. Real reactivity needs a frequency tap, which `just_audio` doesn't expose.

**Option A (recommended) — `audio_waveforms` for visualization only.** Lower lift, cross-platform, gives real amplitude/waveform data you can map to the glow radius/alpha. It runs its own extractor, so plan how it coexists with `just_audio` playback (use it for the *visual* sampling of the current file; keep `just_audio` as the playback engine). Map its amplitude stream onto the existing `glowRadius`/`glowAlpha` in `player_page.dart`'s `_ArtworkSection` instead of the sine expression. Still gate behind `immersiveCanvas` and the §1 "only while sheet open + playing" rule so it can't reheat the phone.

**Option B (max fidelity) — platform-channel audio tap + FFT.** iOS: `MTAudioProcessingTap` on the `AVPlayer` audio mix → FFT (Accelerate/vDSP). Android: `Visualizer` API (`android.media.audiofx.Visualizer`) → FFT buckets. Stream low/mid/high band energy back over a `MethodChannel`/`EventChannel` into the controller, expose as a `ValueNotifier<double> bassEnergy`, and feed the glow from it. This is the "correct" version your docs flag as a future enhancement, but it's the most work and platform-specific.

**Either way:** drive the glow from a `ValueNotifier` (like §1.5), wrap the artwork glow in a `RepaintBoundary`, and keep the animation gated so the visualizer never runs behind a closed sheet — preserving the heat fix.

---

## 8. Ship as version 1.0.3 (bump + Android rebuild + release)

### 8.1 Bump the version
`pubspec.yaml`:
```yaml
version: 1.0.3+4   # was 1.0.2+3 — bump both name and build number
```

### 8.2 Surface the version in the app's Settings
Cleanest: add `package_info_plus` and read it at runtime so it never drifts from pubspec.
```yaml
# pubspec.yaml dependencies
package_info_plus: ^<latest>
```
```dart
// in Settings (Developer card or a new "About" row)
final info = await PackageInfo.fromPlatform();
final versionLabel = 'Version ${info.version} (${info.buildNumber})'; // "Version 1.0.3 (4)"
```
If you'd rather not add a dependency, add a const and show it (remember to update it each release):
```dart
// design_tokens.dart or a constants file
const kAppVersion = '1.0.3';
```
Show it as a row in Settings → Developer/About: `Text('Version $kAppVersion')`.

### 8.3 Rebuild the Android APK on your computer
From the repo root (your dev machine — Android SDK + the vendored `third_party/` overrides handle the rest):
```sh
flutter pub get
flutter analyze            # must be clean
flutter test               # widget regressions
python branding/gen_icon.py            # regenerate the per-accent + default icons
flutter pub run flutter_launcher_icons # rebake the primary launcher icon (coral default)
flutter build apk --release            # arm64, shrunk — your standard release artifact
# output: build/app/outputs/flutter-apk/app-release.apk  → rename to monolith.apk
```
> If you also produce the unsigned IPA, that's the CI job on the `v1.0.3` tag (no Apple Developer Program needed) — same as 1.0.2. The new alternate icons must be committed before tagging so CI bakes them into the IPA.

### 8.4 Update the CHANGELOG
Prepend to `CHANGELOG.md`:
```markdown
## [1.0.3] — <release date>

### Fixed
- **iOS: freshly downloaded songs now play on the first tap** — previously a download had to be followed by a force-quit + relaunch before it would play; the new track's audio source is now loaded as soon as the download completes.
- **Heat & battery drain** — the app no longer schedules a per-frame callback on every state change during playback, and the playback progress bar now repaints in isolation; the SoC gets idle gaps back, so the phone stays cool and the battery lasts longer.

### Added
- **Haptic feedback** for taps and transport controls (toggle in Settings → Playback).
- **Apple Music import toggle** and a **Monolith folder** shortcut in Settings.
- **Smart playlists** — Recently added, Most played, Never played.
- **Lyrics view** — embedded ID3 (USLT) and `.lrc` sidecar support with synced highlighting.
- **Equalizer** (Android) with per-band control.
- **Reactive visualizer** driven by real audio data instead of a fixed waveform.
- **Per-accent app icons** (Android + iOS) plus an in-app logo that follows the selected accent.

### Changed
- One-time Apple Music import prompt buttons relabeled to **Import / Cancel**, with a way to re-trigger it from Settings.

[1.0.3]: https://github.com/naveed-gung/Monolith/releases/tag/v1.0.3
```

### 8.5 Re-release
1. Commit everything (icons, code, CHANGELOG, pubspec bump).
2. Tag: `git tag v1.0.3 && git push origin v1.0.3` (this triggers the unsigned-IPA CI workflow, same as before).
3. Create the GitHub release **1.0.3**, attach the freshly built `monolith.apk` (from §8.3) and the CI-built `monolith.ipa`.
4. Carry over the install notes (AltStore / Sideloadly / **TrollStore Lite** for iOS 16.7.x; APK for Android 7+).

---

## Build / verify checklist (all items)
```sh
flutter pub get
flutter analyze
flutter test
flutter run --profile          # verify §0 playback fix and §1 heat fix on device
python branding/gen_icon.py
flutter pub run flutter_launcher_icons
flutter build apk --release    # §8.3 Android artifact
flutter build ios --release --no-codesign
```
**Order of work:** §0 (playback) → §1/§2 (heat, same fix) → §5 (haptics) → §3 → §4 → §7 features → §6 icons → §8 release. Re-test temperature *and* first-tap playback before bundling the 1.0.3 release so you can attribute each fix cleanly.
