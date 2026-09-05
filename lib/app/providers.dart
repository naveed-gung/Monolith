import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/platform_channels/media_import_channel.dart';
import '../data/repositories/import_export_repository.dart';
import '../data/repositories/playback_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/services/audio/playback_engine.dart';
import '../data/services/audio/playback_service.dart';
import '../data/services/downloads/download_manager.dart';
import '../data/services/downloads/source_provider.dart';
import '../data/services/downloads/youtube_explode_provider.dart';
import '../data/services/media_library/device_media_service.dart';
import '../data/services/storage/library_store.dart';

/// Dependency wiring for the Monolith 2.0 layers.
///
/// Bootstrap contract:
/// 1. [sharedPrefsProvider] must be overridden with an initialized instance
///    before anything reads it.
/// 2. **Background audio init order is critical** (docs/media-playback.md):
///    `JustAudioBackground.init(...)` must complete in `main()` BEFORE
///    `runApp()` — before any [PlaybackService] loads an audio source. The
///    upcoming bootstrap phase wires this; nothing in this file may trigger
///    audio loading eagerly. [playbackEngineProvider] only constructs the
///    player object, which is safe pre-init; `loadTrack` is not.
/// ```dart
/// await JustAudioBackground.init(
///   androidNotificationChannelId: 'com.example.monolith.channel.audio',
///   androidNotificationChannelName: 'Monolith',
///   androidNotificationOngoing: true,
/// );
/// runApp(ProviderScope(overrides: [...], child: const MonolithApp()));
/// ```

/// Resolves Monolith's root data directory. Override in tests to point at a
/// temporary directory.
final rootDirProvider = Provider<RootDirFactory>(
  (ref) => LibraryStore.defaultRootDirectory,
);

/// Versioned library persistence (atomic writes, pruning, disk merge).
final libraryStoreProvider = Provider<LibraryStore>(
  (ref) => LibraryStore(rootDirFactory: ref.watch(rootDirProvider)),
);

/// Initialized [SharedPreferences]; see the bootstrap contract above.
final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(
    'sharedPrefsProvider must be overridden with an initialized '
    'SharedPreferences instance during app bootstrap.',
  ),
);

/// Typed settings facade over [sharedPrefsProvider].
final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(sharedPrefsProvider)),
);

/// Typed bridge to the native `monolith/media_import` module (iOS Swift +
/// Android Kotlin).
final mediaImportChannelProvider = Provider<MediaImportChannel>(
  (ref) => MediaImportChannel(),
);

/// Scratch-directory factory used for backup zips and restore staging.
/// Override during app bootstrap (e.g. `(await getTemporaryDirectory())`)
/// or in tests with a temporary directory — same contract as
/// [sharedPrefsProvider].
final tempDirProvider = Provider<Directory Function()>(
  (ref) => throw UnimplementedError(
    'tempDirProvider must be overridden with a scratch-directory factory '
    'during app bootstrap.',
  ),
);

/// One-tap import/export/backup orchestration over the library store and
/// the native media-import module.
final importExportRepositoryProvider = Provider<ImportExportRepository>(
  (ref) => ImportExportRepository(
    channel: ref.watch(mediaImportChannelProvider),
    libraryStore: ref.watch(libraryStoreProvider),
    tempDirProvider: ref.watch(tempDirProvider),
  ),
);

// ---------------------------------------------------------------------------
// Playback (P3)
// ---------------------------------------------------------------------------

/// Raw audio engine behind [PlaybackEngine]. Swap or fake freely — the
/// repository never sees just_audio types. Requires JustAudioBackground.init
/// to have run before any loadTrack call (see the bootstrap contract above).
final playbackEngineProvider = Provider<PlaybackEngine>(
  (ref) => PlaybackService(),
);

/// Queue/repeat/shuffle orchestrator. Disposing releases engine resources
/// and all ValueNotifiers.
final playbackRepositoryProvider = Provider<PlaybackRepository>((ref) {
  final repository = PlaybackRepository(
    engine: ref.watch(playbackEngineProvider),
    libraryStore: ref.watch(libraryStoreProvider),
  );
  ref.onDispose(repository.dispose);
  return repository;
});

/// Android MediaStore scanner (iOS intentionally returns empty — device
/// library import there goes through importFromMusicApp instead).
final deviceMediaServiceProvider = Provider<DeviceMediaService>(
  (ref) => DeviceMediaService(),
);

// ---------------------------------------------------------------------------
// Downloads (P4)
// ---------------------------------------------------------------------------

/// Downloadable source kinds. Add a provider here and the manager picks it
/// up automatically (first successful inspect wins).
final sourceProvidersProvider = Provider<List<SourceProvider>>((ref) {
  return [
    YoutubeExplodeProvider(
      destinationDirectory: () =>
          ref.watch(libraryStoreProvider).musicDirectory(),
    ),
  ];
});

/// Persistent download queue with Wi-Fi-only gating. The initial gate value
/// comes from user settings; the UI updates it via
/// `manager.setWifiOnly(settings.setDownloadsOnWifi(...))`.
final downloadManagerProvider = Provider<DownloadManager>((ref) {
  final manager = DownloadManager(
    providers: ref.watch(sourceProvidersProvider),
    libraryStore: ref.watch(libraryStoreProvider),
    connectivityProbe: ConnectivityPlusProbe(),
    wifiOnly: ref.watch(settingsRepositoryProvider).downloadsOnWifi,
  );
  ref.onDispose(manager.dispose);
  // Restore persisted tasks + start the pump after first read. Fire-and-
  // forget so provider construction stays synchronous; restore failures are
  // swallowed inside the manager and surface as an empty queue instead of a
  // crashed boot.
  unawaited(manager.initialize());
  return manager;
});
