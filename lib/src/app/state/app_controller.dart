import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/music_models.dart';
import '../theme/design_tokens.dart';
import '../../core/services/download_store.dart';
import '../../core/services/local_media_service.dart';
import '../../core/services/media_downloader.dart';
import '../../core/services/media_downloader_models.dart';
import '../../core/services/manual_audio_import_service.dart';
import '../../core/services/haptics_service.dart';

class MonolithController extends ChangeNotifier {
  // SharedPreferences keys
  static const _kTheme = 'pref_theme';
  static const _kAccent = 'pref_accent';
  static const _kWifi = 'pref_wifi_only';
  static const _kNormalize = 'pref_normalize';
  static const _kTransitions = 'pref_transitions';
  static const _kCanvas = 'pref_canvas';
  static const _kHaptics = 'pref_haptics';
  static const _kSeenImportPrompt = 'pref_seen_import_prompt';

  MonolithController({
    LocalMediaService? localMediaService,
    DownloadStore? downloadStore,
    AudioPlayer? audioPlayer,
    MediaDownloader? mediaDownloader,
    ManualAudioImportService? manualAudioImportService,
  }) : _localMediaService = localMediaService ?? LocalMediaService(),
       _downloadStore = downloadStore ?? DownloadStore(),
       _audioPlayer = audioPlayer ?? AudioPlayer(),
       _youtubeDL = mediaDownloader ?? MediaDownloader.platform(),
       _manualAudioImportService =
           manualAudioImportService ?? ManualAudioImportService() {
    _bindAudioPlayer();
    _bindDownloader();
    _bindConnectivity();
    _ready = _bootstrap();
  }

  /// Completes once preferences are loaded and the initial library scan has
  /// run. Used by the startup Apple Music import prompt so it only decides
  /// after the persisted "seen" flag is available.
  late final Future<void> _ready;
  Future<void> get whenReady => _ready;

  final LocalMediaService _localMediaService;
  final DownloadStore _downloadStore;
  final AudioPlayer _audioPlayer;
  final MediaDownloader _youtubeDL;
  final ManualAudioImportService _manualAudioImportService;
  SharedPreferences? _prefs;

  late final StreamSubscription<PlayerState> _playerStateSubscription;
  late final StreamSubscription<Duration> _playerPositionSubscription;
  late final StreamSubscription<Duration?> _playerDurationSubscription;
  late final StreamSubscription<DownloadProgress> _downloadProgressSubscription;
  late final StreamSubscription<DownloadState> _downloadStateSubscription;
  late final StreamSubscription<DownloadError> _downloadErrorSubscription;
  late final StreamSubscription<LogMessage> _downloadLogSubscription;
  late final StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;

  AppTab _currentTab = AppTab.downloads;
  LibraryCategory _selectedCategory = LibraryCategory.tracks;
  ThemePreference _themePreference = ThemePreference.system;
  AccentPreset _accentPreset = AccentSwatch.fallback;
  RepeatMode _repeatMode = RepeatMode.all;

  int _selectedTrackIndex = 0;
  bool _isPlaying = false;
  bool _shuffleEnabled = false;
  String _searchQuery = '';

  List<Track> _tracks = const [];
  List<Track> _deviceTracks = const [];
  List<Track> _downloadedTracks = const [];
  List<DownloadTaskInfo> _downloadTasks = const [];

  bool _isLibraryLoading = true;
  bool _hasLibraryPermission = false;
  String? _libraryError;
  bool _isImportingAudio = false;
  bool _isDownloaderReady = false;
  String? _downloaderError;
  bool _hasAttemptedYoutubeDlRefresh = false;

  Duration _currentPosition = Duration.zero;
  Duration? _currentTrackDuration;
  bool _completionHandled = false;

  /// Live playback position + [0,1] progress, exposed as listenables so the
  /// seek bar and time labels can repaint in isolation instead of rebuilding
  /// the whole shell on every position tick. This is the big heat/battery win:
  /// the position stream no longer calls notifyListeners().
  final ValueNotifier<Duration> positionListenable =
      ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<double> progress = ValueNotifier<double>(0);

  List<ConnectivityResult> _connectivityResults = const [ConnectivityResult.wifi];

  bool _downloadsOnWifi = true;
  bool _normalizeAudio = true;
  bool _smoothTransitions = true;
  bool _immersiveCanvas = true;
  bool _hapticsEnabled = true;
  final HapticsService _haptics = HapticsService();
  bool _isPlayerOpen = false;
  bool _iosAppleMusicImportEnabled =
      defaultTargetPlatform != TargetPlatform.iOS;
  bool _hasSeenImportPrompt = false;
  final Set<String> _pauseRequestedProcessIds = <String>{};
  final Map<String, String> _fatalDownloadErrors = <String, String>{};
  final Map<String, Set<String>> _playlistTrackIds = {'Favorites': <String>{}};

  List<Track> get tracks => _tracks;

  AppTab get currentTab => _currentTab;
  LibraryCategory get selectedCategory => _selectedCategory;
  ThemePreference get themePreference => _themePreference;
  AccentPreset get accentPreset => _accentPreset;
  RepeatMode get repeatMode => _repeatMode;
  Track? get currentTrack => _tracks.isEmpty
      ? null
      : _tracks[_selectedTrackIndex.clamp(0, _tracks.length - 1)];
  bool get hasCurrentTrack => _tracks.isNotEmpty;
  bool get isPlaying => _isPlaying;
  bool get shuffleEnabled => _shuffleEnabled;
  Duration get currentTrackDuration =>
      _currentTrackDuration ?? currentTrack?.duration ?? Duration.zero;
  double get playbackProgress {
    final totalMilliseconds = currentTrackDuration.inMilliseconds;
    if (totalMilliseconds == 0) {
      return 0;
    }
    return (_currentPosition.inMilliseconds / totalMilliseconds).clamp(0, 1);
  }

  String get searchQuery => _searchQuery;
  bool get isOnline =>
      _connectivityResults.any((r) => r != ConnectivityResult.none);
  bool get downloadsOnWifi => _downloadsOnWifi;
  bool get normalizeAudio => _normalizeAudio;
  bool get smoothTransitions => _smoothTransitions;
  bool get immersiveCanvas => _immersiveCanvas;
  bool get hapticsEnabled => _hapticsEnabled;
  bool get isPlayerOpen => _isPlayerOpen;
  bool get supportsAppleMusicImportPrompt =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  bool get isAppleMusicImportEnabled => _iosAppleMusicImportEnabled;

  /// Whether the one-time "Import from Apple Music" prompt should still be
  /// shown on iOS. False once dismissed/acted on (persisted) or off-platform.
  bool get shouldShowImportPrompt =>
      supportsAppleMusicImportPrompt && !_hasSeenImportPrompt;

  Future<void> markImportPromptSeen() async {
    if (_hasSeenImportPrompt) return;
    _hasSeenImportPrompt = true;
    await _prefs?.setBool(_kSeenImportPrompt, true);
  }
  bool get isLibraryLoading => _isLibraryLoading;
  bool get hasLibraryPermission => _hasLibraryPermission;
  String? get libraryError => _libraryError;
  bool get isImportingAudio => _isImportingAudio;
  bool get isDownloaderReady => _isDownloaderReady;
  String? get downloaderError => _downloaderError;
  List<DownloadTaskInfo> get downloadTasks => _downloadTasks;
  List<Track> get offlineTracks => _downloadedTracks;
  List<String> get playlistNames =>
      _playlistTrackIds.keys.toList(growable: false);
  List<Track> tracksForPlaylist(String playlistName) {
    final trackIds = _playlistTrackIds[playlistName];
    if (trackIds == null || trackIds.isEmpty) {
      return const [];
    }

    return tracks
        .where((track) => trackIds.contains(track.id))
        .toList(growable: false);
  }

  Track? leadTrackForPlaylist(String playlistName) {
    final playlistTracks = tracksForPlaylist(playlistName);
    if (playlistTracks.isEmpty) {
      return null;
    }
    return playlistTracks.first;
  }

  bool get hasSearchFilters => _searchQuery.isNotEmpty;
  bool get hasPlayableTracks => tracks.any((track) => track.canPlay);

  ThemeMode get themeMode {
    switch (_themePreference) {
      case ThemePreference.system:
        return ThemeMode.system;
      case ThemePreference.light:
        return ThemeMode.light;
      case ThemePreference.dark:
        return ThemeMode.dark;
    }
  }

  String get queueLabel {
    switch (currentTrack?.source) {
      case TrackSource.mock:
        return 'Placeholder';
      case TrackSource.device:
        return 'On device';
      case TrackSource.downloaded:
        return 'Downloaded';
      case TrackSource.imported:
        return 'Imported';
      case null:
        return '';
    }
  }

  Duration get currentPosition => _currentPosition;

  List<Track> get highlightedTracks {
    return tracks.take(4).toList(growable: false);
  }

  List<String> get libraryArtists {
    final artists = <String>{};
    for (final track in tracks) {
      artists.add(track.artist);
    }
    return artists.toList(growable: false);
  }

  List<Track> get albumHighlights {
    final seen = <String>{};
    final albums = <Track>[];
    for (final track in tracks) {
      final albumKey = track.album.toLowerCase();
      if (seen.add(albumKey)) {
        albums.add(track);
      }
    }
    return albums;
  }

  List<Track> get searchResults {
    if (_searchQuery.isEmpty) {
      return tracks;
    }

    final query = _searchQuery.toLowerCase();
    return tracks.where((track) {
      final haystack = [
        track.title,
        track.artist,
        track.album,
        track.genre,
        track.blurb,
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  List<Track> get upNextTracks {
    final queue = _queueIndicesForNavigation();
    if (queue.length <= 1) {
      return const [];
    }

    final currentPosition = queue.indexOf(_selectedTrackIndex);
    if (currentPosition == -1) {
      return const [];
    }

    final rotated = [
      ...queue.skip(currentPosition + 1),
      ...queue.take(currentPosition),
    ];

    return rotated.take(3).map((index) => tracks[index]).toList();
  }

  void selectTab(AppTab tab) {
    final nextCategory = switch (tab) {
      AppTab.library =>
        _selectedCategory == LibraryCategory.playlists
            ? LibraryCategory.tracks
            : _selectedCategory,
      AppTab.downloads =>
        _selectedCategory == LibraryCategory.playlists
            ? LibraryCategory.tracks
            : _selectedCategory,
      AppTab.search => _selectedCategory,
    };

    if (_currentTab == tab &&
        _selectedCategory == nextCategory &&
        !_isPlayerOpen) {
      return;
    }

    _currentTab = tab;
    _selectedCategory = nextCategory;
    _isPlayerOpen = false;
    notifyListeners();
  }

  void selectLibraryCategory(LibraryCategory category) {
    final nextTab = _currentTab == AppTab.downloads
        ? AppTab.library
        : _currentTab;

    if (_selectedCategory == category && nextTab == _currentTab) {
      return;
    }

    _selectedCategory = category;
    _currentTab = nextTab;
    notifyListeners();
  }

  void selectTrack(
    Track track, {
    bool openPlayer = false,
    bool autoplay = true,
  }) {
    final index = tracks.indexWhere((candidate) => candidate.id == track.id);
    if (index == -1) {
      return;
    }
    unawaited(
      _activateTrackIndex(index, openPlayer: openPlayer, autoplay: autoplay),
    );
  }

  void openPlayer() {
    if (_isPlayerOpen || currentTrack == null) {
      return;
    }

    _isPlayerOpen = true;
    notifyListeners();
  }

  void closePlayer() {
    if (!_isPlayerOpen) {
      return;
    }

    _isPlayerOpen = false;
    notifyListeners();
  }

  Future<void> togglePlayback() async {
    if (currentTrack?.canPlay != true) {
      return;
    }

    if (_audioPlayer.playing) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play();
    }
  }

  void nextTrack({bool openPlayer = false}) {
    unawaited(_moveQueue(1, openPlayer: openPlayer, autoplay: true));
  }

  void previousTrack() {
    if (_currentPosition > const Duration(seconds: 8)) {
      unawaited(_audioPlayer.seek(Duration.zero));
      return;
    }
    unawaited(_moveQueue(-1, autoplay: _isPlaying));
  }

  void toggleShuffle() {
    _shuffleEnabled = !_shuffleEnabled;
    notifyListeners();
  }

  void cycleRepeatMode() {
    switch (_repeatMode) {
      case RepeatMode.off:
        _repeatMode = RepeatMode.all;
      case RepeatMode.all:
        _repeatMode = RepeatMode.one;
      case RepeatMode.one:
        _repeatMode = RepeatMode.off;
    }
    notifyListeners();
  }

  Future<void> setPlaybackProgress(double value) async {
    final totalDuration = currentTrackDuration;
    if (currentTrack?.canPlay != true || totalDuration == Duration.zero) {
      return;
    }

    final nextPosition = Duration(
      milliseconds: (totalDuration.inMilliseconds * value.clamp(0.0, 1.0))
          .round(),
    );
    await _audioPlayer.seek(nextPosition);
  }

  void setSearchQuery(String query) {
    final next = query.trimLeft();
    if (next == _searchQuery) {
      return;
    }
    _searchQuery = next;
    notifyListeners();
  }

  void clearSearchFilters() {
    _searchQuery = '';
    notifyListeners();
  }

  void setThemePreference(ThemePreference preference) {
    if (_themePreference == preference) return;
    _themePreference = preference;
    _prefs?.setString(_kTheme, preference.name);
    notifyListeners();
  }

  void setAccentPreset(AccentPreset preset) {
    if (_accentPreset == preset) return;
    _accentPreset = preset;
    _prefs?.setString(_kAccent, preset.name);
    notifyListeners();
  }

  void setDownloadsOnWifi(bool value) {
    if (_downloadsOnWifi == value) return;
    _downloadsOnWifi = value;
    _prefs?.setBool(_kWifi, value);
    notifyListeners();
  }

  void setNormalizeAudio(bool value) {
    if (_normalizeAudio == value) return;
    _normalizeAudio = value;
    _prefs?.setBool(_kNormalize, value);
    unawaited(_applyAudioVolume());
    notifyListeners();
  }

  void setSmoothTransitions(bool value) {
    if (_smoothTransitions == value) return;
    _smoothTransitions = value;
    _prefs?.setBool(_kTransitions, value);
    notifyListeners();
  }

  void setImmersiveCanvas(bool value) {
    if (_immersiveCanvas == value) return;
    _immersiveCanvas = value;
    _prefs?.setBool(_kCanvas, value);
    notifyListeners();
  }

  void setHapticsEnabled(bool value) {
    if (_hapticsEnabled == value) return;
    _hapticsEnabled = value;
    _haptics.enabled = value;
    _prefs?.setBool(_kHaptics, value);
    // Confirm the new state with a tap when turning it on.
    if (value) _haptics.tap(HapticStrength.selection);
    notifyListeners();
  }

  /// Fire a haptic tap for a user interaction (respects the global toggle).
  /// Call this from UI gesture handlers — never from audio/stream callbacks.
  void hapticTap([HapticStrength strength = HapticStrength.light]) =>
      _haptics.tap(strength);

  // ── Audio helpers ──────────────────────────────────────────────────────

  Future<void> _applyAudioVolume() async {
    // Normalize: mild gain reduction (~−1.5 dB) to tame hot masters.
    await _audioPlayer.setVolume(_normalizeAudio ? 0.84 : 1.0);
  }

  Future<void> _fadeVolume({required double to, int ms = 220}) async {
    if (!_smoothTransitions) {
      await _audioPlayer.setVolume(to);
      return;
    }
    const steps = 12;
    final from = _audioPlayer.volume;
    final diff = (to - from) / steps;
    final stepMs = ms ~/ steps;
    for (var i = 1; i <= steps; i++) {
      await Future.delayed(Duration(milliseconds: stepMs));
      await _audioPlayer.setVolume((from + diff * i).clamp(0.0, 1.0));
    }
  }

  Future<void> _checkConnectivity() async {
    if (!_downloadsOnWifi) return;
    final results = await Connectivity().checkConnectivity();
    if (results.any((r) => r == ConnectivityResult.wifi)) return;
    throw StateError(
      'Downloads are set to Wi-Fi only. Connect to Wi-Fi and try again.',
    );
  }

  Future<void> setAppleMusicImportEnabled(
    bool value, {
    bool retryPermissionRequest = false,
  }) async {
    if (!supportsAppleMusicImportPrompt) {
      return;
    }

    if (_iosAppleMusicImportEnabled == value &&
        (!value || _hasLibraryPermission || _deviceTracks.isNotEmpty)) {
      return;
    }

    _iosAppleMusicImportEnabled = value;

    if (!value && _deviceTracks.isEmpty && !_hasLibraryPermission) {
      return;
    }

    await refreshLibrary(
      retryPermissionRequest: value && retryPermissionRequest,
    );
  }

  Future<void> refreshLibrary({bool retryPermissionRequest = false}) async {
    _isLibraryLoading = true;
    notifyListeners();

    final previousTrackId = currentTrack?.id;
    try {
      final shouldLoadDeviceLibrary =
          !supportsAppleMusicImportPrompt ||
          _iosAppleMusicImportEnabled ||
          retryPermissionRequest;

      _downloadedTracks = await _downloadStore.loadTracks();
      final mediaSnapshot = await _localMediaService.loadTracks(
        retryRequest: retryPermissionRequest,
        requestPermission: shouldLoadDeviceLibrary,
      );

      _hasLibraryPermission =
          shouldLoadDeviceLibrary && mediaSnapshot.permissionGranted;
      _libraryError = shouldLoadDeviceLibrary ? mediaSnapshot.error : null;
      _deviceTracks = mediaSnapshot.tracks;
      _rebuildTracks(preferredTrackId: previousTrackId);

      await _syncSelectedTrack(autoplay: false);
    } catch (error) {
      _libraryError = 'Unable to refresh your library: $error';
    } finally {
      _isLibraryLoading = false;
      notifyListeners();
    }
  }

  Future<String?> importAudioFiles() async {
    if (_isImportingAudio) {
      return null;
    }

    _isImportingAudio = true;
    notifyListeners();

    try {
      final pickedFiles = await _manualAudioImportService.pickAudioFiles();
      if (pickedFiles.isEmpty) {
        return null;
      }

      final previousTrackId = currentTrack?.id;
      final importedTracks = <Track>[];
      var failedCount = 0;

      for (var index = 0; index < pickedFiles.length; index++) {
        final pickedFile = pickedFiles[index];
        if (!pickedFile.hasReadableContent) {
          failedCount += 1;
          continue;
        }

        try {
          final safeFileName = _sanitizeImportedFileName(pickedFile.name);
          final storedFile = await _downloadStore.saveImportedAudio(
            preferredFileName: safeFileName,
            sourcePath: pickedFile.path,
            bytes: pickedFile.bytes,
          );
          final artworkFilePath = await _downloadStore.findArtworkForAudio(
            storedFile.path,
          );
          final displayTitle = _titleFromFileName(safeFileName);

          importedTracks.add(
            Track(
              id: 'import-${DateTime.now().microsecondsSinceEpoch}-$index',
              title: displayTitle,
              artist: 'Files import',
              album: 'Imported audio',
              genre: 'Imported audio',
              duration: Duration.zero,
              colors: Track.paletteForSeed(storedFile.path),
              blurb: 'Imported from Files for offline playback.',
              source: TrackSource.imported,
              filePath: storedFile.path,
              artworkFilePath: artworkFilePath,
            ),
          );
        } catch (_) {
          failedCount += 1;
        }
      }

      if (importedTracks.isEmpty) {
        throw StateError(
          'No audio files were imported. Try exporting the audio to the Files app first.',
        );
      }

      _downloadedTracks = [
        ...importedTracks,
        ..._downloadedTracks.where(
          (existing) => importedTracks.every(
            (track) => track.filePath != existing.filePath,
          ),
        ),
      ];
      await _downloadStore.saveTracks(_downloadedTracks);

      _rebuildTracks(
        preferredTrackId: previousTrackId ?? importedTracks.first.id,
      );
      await _syncSelectedTrack(autoplay: false);
      notifyListeners();

      final importedCount = importedTracks.length;
      if (failedCount == 0) {
        return importedCount == 1
            ? 'Imported 1 audio file from Files.'
            : 'Imported $importedCount audio files from Files.';
      }

      return importedCount == 1
          ? 'Imported 1 audio file. $failedCount file(s) could not be added.'
          : 'Imported $importedCount audio files. $failedCount file(s) could not be added.';
    } catch (error) {
      final message = error is StateError
          ? error.message.toString()
          : 'Could not import audio from Files.';
      throw StateError(message);
    } finally {
      _isImportingAudio = false;
      notifyListeners();
    }
  }

  Future<String> renameTrackMetadata({
    required Track track,
    required String title,
    String? artist,
    String? album,
  }) async {
    final resolvedTitle = title.trim().isEmpty ? track.title : title.trim();
    final resolvedArtist = artist == null || artist.trim().isEmpty
        ? track.artist
        : artist.trim();
    final resolvedAlbum = album == null || album.trim().isEmpty
        ? track.album
        : album.trim();

    final updatedTrack = track.copyWith(
      title: resolvedTitle,
      artist: resolvedArtist,
      album: resolvedAlbum,
    );

    final tIdx = _tracks.indexWhere((t) => t.id == track.id);
    if (tIdx != -1) {
      final updated = List<Track>.of(_tracks);
      updated[tIdx] = updatedTrack;
      _tracks = List.unmodifiable(updated);
    }

    if (track.source == TrackSource.downloaded ||
        track.source == TrackSource.imported) {
      final dIdx = _downloadedTracks.indexWhere((t) => t.id == track.id);
      if (dIdx != -1) {
        final updated = List<Track>.of(_downloadedTracks);
        updated[dIdx] = updatedTrack;
        _downloadedTracks = List.unmodifiable(updated);
      }
      await _downloadStore.saveTracks(_downloadedTracks);
    }

    notifyListeners();
    return 'Updated ${updatedTrack.title}.';
  }

  Future<String> deleteTrack(Track track) async {
    if (track.source == TrackSource.device) {
      return 'Device tracks cannot be deleted from Monolith yet.';
    }

    final previousTrackId = currentTrack?.id == track.id
        ? null
        : currentTrack?.id;
    _downloadedTracks = _downloadedTracks
        .where((existing) => existing.id != track.id)
        .toList(growable: false);
    await _downloadStore.saveTracks(_downloadedTracks);
    await _downloadStore.deleteArtifactsForTrack(track);
    _removeTrackFromPlaylists(track.id);

    _rebuildTracks(preferredTrackId: previousTrackId);
    await _syncSelectedTrack(autoplay: false);
    notifyListeners();
    return 'Removed ${track.title} from your library.';
  }

  String addTrackToPlaylist({
    required Track track,
    required String playlistName,
  }) {
    final normalizedName = playlistName.trim();
    if (normalizedName.isEmpty) {
      return 'Choose a playlist name first.';
    }

    final trackIds = _playlistTrackIds.putIfAbsent(
      normalizedName,
      () => <String>{},
    );
    final inserted = trackIds.add(track.id);
    notifyListeners();

    if (inserted) {
      return 'Added ${track.title} to $normalizedName.';
    }

    return '${track.title} is already in $normalizedName.';
  }

  Future<String> getDownloadDirectoryPath() async {
    final dir = await _downloadStore.getDownloadDirectory();
    return dir.path;
  }

  void createEmptyPlaylist(String name) {
    final n = name.trim();
    if (n.isEmpty) return;
    _playlistTrackIds.putIfAbsent(n, () => <String>{});
    notifyListeners();
  }

  String removeTrackFromPlaylist({
    required Track track,
    required String playlistName,
  }) {
    final trackIds = _playlistTrackIds[playlistName];
    if (trackIds == null) return 'Playlist not found.';
    trackIds.remove(track.id);
    notifyListeners();
    return 'Removed ${track.title} from $playlistName.';
  }

  Future<DownloadPreview> inspectDownload(String rawUrl) async {
    final url = rawUrl.trim();
    if (url.isEmpty) {
      throw StateError('Paste a media link first.');
    }

    await _ensureDownloaderReady();

    final info = await _youtubeDL.getVideoInfo(url);
    final title = (info.title == null || info.title!.trim().isEmpty)
        ? 'Downloaded audio'
        : info.title!.trim();

    return DownloadPreview(
      url: url,
      title: title,
      suggestedFileName: _sanitizeFileName(title),
      uploader: info.uploader,
      thumbnailUrl: info.thumbnail,
      duration: info.duration == null
          ? null
          : Duration(seconds: info.duration!),
      estimatedSizeBytes: _estimateDownloadSize(info),
    );
  }

  Future<void> startAudioDownload({
    required DownloadPreview preview,
    required String fileName,
  }) async {
    await _checkConnectivity();
    final sanitizedName = _sanitizeFileName(
      fileName.trim().isEmpty ? preview.suggestedFileName : fileName.trim(),
    );
    final processId = 'audio_${DateTime.now().millisecondsSinceEpoch}';

    await _startManagedDownload(
      DownloadTaskInfo(
        processId: processId,
        url: preview.url,
        title: preview.title,
        fileName: sanitizedName,
        uploader: preview.uploader,
        thumbnailUrl: preview.thumbnailUrl,
        status: DownloadTaskStatus.ready,
        mediaDuration: preview.duration,
        totalBytes: preview.estimatedSizeBytes,
      ),
    );
  }

  Future<void> pauseDownload(String processId) async {
    final task = _downloadTaskById(processId);
    if (!task.canPause) {
      return;
    }

    _pauseRequestedProcessIds.add(processId);
    _upsertDownloadTask(
      task.copyWith(
        status: DownloadTaskStatus.paused,
        errorMessage: null,
        detailLog: _appendTaskLog(
          task.detailLog,
          'Download paused. Tap play to continue.',
          LogLevel.info,
        ),
      ),
    );

    final cancelled = await _youtubeDL.cancelDownload(processId);
    if (cancelled) {
      return;
    }

    _pauseRequestedProcessIds.remove(processId);
    _upsertDownloadTask(
      task.copyWith(
        status: DownloadTaskStatus.downloading,
        detailLog: _appendTaskLog(
          task.detailLog,
          'Pause failed. Download kept running.',
          LogLevel.warning,
        ),
      ),
    );
  }

  Future<void> resumeDownload(String processId) async {
    final task = _downloadTaskById(processId);
    if (!task.canResume) {
      return;
    }

    await _startManagedDownload(
      task.copyWith(
        status: DownloadTaskStatus.ready,
        eta: Duration.zero,
        errorMessage: null,
        detailLog: _appendTaskLog(
          task.detailLog,
          'Resuming download.',
          LogLevel.info,
        ),
      ),
    );
  }

  Future<void> retryDownload(String processId) async {
    final task = _downloadTaskById(processId);
    if (!task.canRetry) {
      return;
    }

    await _startManagedDownload(
      task.copyWith(
        status: DownloadTaskStatus.ready,
        progress: 0,
        eta: Duration.zero,
        errorMessage: null,
        detailLog: _appendTaskLog(
          task.detailLog,
          'Retrying download.',
          LogLevel.info,
        ),
      ),
    );
  }

  Future<void> _startManagedDownload(DownloadTaskInfo task) async {
    await _ensureDownloaderReady();
    _pauseRequestedProcessIds.remove(task.processId);
    _fatalDownloadErrors.remove(task.processId);
    _upsertDownloadTask(task);

    final outputDirectory = await _downloadStore.getDownloadDirectory();
    final request = _buildAudioDownloadRequest(
      processId: task.processId,
      url: task.url,
      fileName: task.fileName,
      outputDirectoryPath: outputDirectory.path,
    );
    final preview = DownloadPreview(
      url: task.url,
      title: task.title,
      suggestedFileName: task.fileName,
      uploader: task.uploader,
      thumbnailUrl: task.thumbnailUrl,
      duration: task.mediaDuration,
      estimatedSizeBytes: task.totalBytes,
    );

    final result = await _runAudioDownloadWithRecovery(
      request: request,
      preview: preview,
      processId: task.processId,
    );
    final fatalError = _fatalDownloadErrors.remove(task.processId);
    final wasPauseRequested = _pauseRequestedProcessIds.remove(task.processId);
    if (result.status != OperationStatus.success || result.outputPath == null) {
      final failedTask = _downloadTaskById(task.processId);
      final nextStatus = fatalError != null
          ? DownloadTaskStatus.failed
          : wasPauseRequested
          ? DownloadTaskStatus.paused
          : result.status == OperationStatus.cancelled
          ? DownloadTaskStatus.cancelled
          : DownloadTaskStatus.failed;

      if (nextStatus != DownloadTaskStatus.paused) {
        await _cleanupIncompleteDownload(task);
      }

      _upsertDownloadTask(
        failedTask.copyWith(
          status: nextStatus,
          errorMessage: nextStatus == DownloadTaskStatus.failed
              ? fatalError ??
                    result.errorMessage ??
                    failedTask.errorMessage ??
                    'Download failed.'
              : null,
        ),
      );
      return;
    }

    final hasValidAudioFile = await _downloadStore.hasValidAudioFile(
      result.outputPath!,
    );
    if (!hasValidAudioFile) {
      await _cleanupIncompleteDownload(task);
      _upsertDownloadTask(
        _downloadTaskById(task.processId).copyWith(
          status: DownloadTaskStatus.failed,
          errorMessage: 'Download did not produce a playable audio file.',
        ),
      );
      return;
    }

    final artworkFilePath = await _downloadStore.findArtworkForAudio(
      result.outputPath!,
    );
    final track = Track(
      id: 'download-${task.processId}',
      title: preview.title,
      artist: preview.uploader ?? 'Unknown source',
      album: 'Downloads',
      genre: 'Downloaded audio',
      duration: preview.duration ?? Duration.zero,
      colors: Track.paletteForSeed('${preview.title}-${preview.url}'),
      blurb:
          'Downloaded from ${Uri.tryParse(preview.url)?.host ?? preview.url}',
      source: TrackSource.downloaded,
      filePath: result.outputPath,
      artworkFilePath: artworkFilePath,
      artworkUrl: preview.thumbnailUrl,
    );

    _downloadedTracks = [
      track,
      ..._downloadedTracks.where(
        (existing) => existing.filePath != track.filePath,
      ),
    ];
    _fatalDownloadErrors.remove(task.processId);
    await _downloadStore.saveTracks(_downloadedTracks);
    await _localMediaService.scanMedia(result.outputPath!);

    _rebuildTracks(preferredTrackId: track.id);

    // Load the just-downloaded file into the player engine NOW so the first tap
    // on Play works without a relaunch. Without this the track is selected but
    // no AudioSource is set, and togglePlayback() has nothing to play — the iOS
    // "won't play until the app is killed and reopened" bug. autoplay:false so a
    // finished download doesn't start blasting on its own. Every other path
    // (refreshLibrary, import, delete, bulk-remove) already does this.
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
  }

  Future<void> cancelDownload(String processId) async {
    _pauseRequestedProcessIds.remove(processId);
    final cancelled = await _youtubeDL.cancelDownload(processId);
    if (!cancelled) {
      return;
    }

    _upsertDownloadTask(
      _downloadTaskById(processId).copyWith(
        status: DownloadTaskStatus.cancelled,
        errorMessage: null,
        detailLog: _appendTaskLog(
          _downloadTaskById(processId).detailLog,
          'Download cancelled.',
          LogLevel.info,
        ),
      ),
    );
  }

  Future<void> _moveQueue(
    int direction, {
    bool openPlayer = false,
    required bool autoplay,
  }) async {
    final queue = _queueIndicesForNavigation();
    if (queue.isEmpty) {
      return;
    }

    final currentPosition = queue.indexOf(_selectedTrackIndex);
    if (currentPosition == -1) {
      return;
    }

    var nextPosition = currentPosition;

    if (_shuffleEnabled && queue.length > 1) {
      nextPosition = (currentPosition + direction.abs()) % queue.length;
    } else {
      nextPosition = currentPosition + direction;

      if (nextPosition < 0) {
        nextPosition = _repeatMode == RepeatMode.all ? queue.length - 1 : 0;
      }

      if (nextPosition >= queue.length) {
        nextPosition = _repeatMode == RepeatMode.all ? 0 : queue.length - 1;
      }
    }

    await _activateTrackIndex(
      queue[nextPosition],
      openPlayer: openPlayer,
      autoplay: autoplay,
    );
  }

  List<int> _queueIndicesForNavigation() {
    return List<int>.generate(tracks.length, (index) => index);
  }

  Future<void> _bootstrap() async {
    await _loadPrefs();
    await _configureAudioSession();
    await _initializeDownloader();
    await refreshLibrary();
  }

  Future<void> _loadPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    final p = _prefs!;
    _themePreference = ThemePreference.values.firstWhere(
      (e) => e.name == (p.getString(_kTheme) ?? ''),
      orElse: () => ThemePreference.system,
    );
    _accentPreset = AccentPreset.values.firstWhere(
      (e) => e.name == (p.getString(_kAccent) ?? ''),
      orElse: () => AccentSwatch.fallback,
    );
    _downloadsOnWifi = p.getBool(_kWifi) ?? true;
    _normalizeAudio = p.getBool(_kNormalize) ?? true;
    _smoothTransitions = p.getBool(_kTransitions) ?? true;
    _immersiveCanvas = p.getBool(_kCanvas) ?? true;
    _hapticsEnabled = p.getBool(_kHaptics) ?? true;
    _haptics.enabled = _hapticsEnabled;
    _hasSeenImportPrompt = p.getBool(_kSeenImportPrompt) ?? false;
    notifyListeners();
  }

  Future<void> _configureAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration.music());
  }

  void _bindConnectivity() {
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((results) {
      _connectivityResults = results;
      notifyListeners();
    });
    unawaited(Connectivity().checkConnectivity().then((r) {
      _connectivityResults = r;
      notifyListeners();
    }));
  }

  void _bindAudioPlayer() {
    _playerStateSubscription = _audioPlayer.playerStateStream.listen((state) {
      _isPlaying = state.playing;

      if (state.processingState == ProcessingState.completed) {
        if (_completionHandled) {
          return;
        }
        _completionHandled = true;
        unawaited(_handleTrackCompletion());
      } else {
        _completionHandled = false;
      }

      notifyListeners();
    });

    _playerPositionSubscription = _audioPlayer.positionStream.listen((
      position,
    ) {
      _currentPosition = position;
      positionListenable.value = position;
      final total = currentTrackDuration.inMilliseconds;
      progress.value =
          total == 0 ? 0 : (position.inMilliseconds / total).clamp(0.0, 1.0);
      // Intentionally NO notifyListeners() here — the seek bar and time labels
      // listen to positionListenable/progress and repaint on their own. Shell
      // rebuilds stay reserved for discrete events (play/pause, track change,
      // completion), so the SoC gets idle gaps back.
    });

    _playerDurationSubscription = _audioPlayer.durationStream.listen((
      duration,
    ) {
      _currentTrackDuration =
          duration ?? currentTrack?.duration ?? Duration.zero;
      if (duration != null && duration > Duration.zero) {
        _persistResolvedCurrentTrackDuration(duration);
      }
      // Total changed → recompute progress so the bar is correct immediately.
      final total = currentTrackDuration.inMilliseconds;
      progress.value = total == 0
          ? 0
          : (_currentPosition.inMilliseconds / total).clamp(0.0, 1.0);
      notifyListeners();
    });
  }

  void _bindDownloader() {
    _downloadProgressSubscription = _youtubeDL.onProgress.listen((progress) {
      final existingTask = _downloadTaskById(progress.processId);
      if (existingTask.status == DownloadTaskStatus.paused ||
          existingTask.status == DownloadTaskStatus.cancelled ||
          existingTask.status == DownloadTaskStatus.completed) {
        return;
      }

      _upsertDownloadTask(
        existingTask.copyWith(
          status: DownloadTaskStatus.downloading,
          progress: progress.progressFraction,
          eta: progress.eta,
        ),
      );
    });

    _downloadStateSubscription = _youtubeDL.onStateChanged.listen((state) {
      final existingTask = _downloadTaskById(state.processId);
      final hasFatalFailure = _fatalDownloadErrors.containsKey(state.processId);
      final status = switch (state.state) {
        DownloadStateType.completed => DownloadTaskStatus.completed,
        DownloadStateType.cancelled =>
          hasFatalFailure
              ? DownloadTaskStatus.failed
              : _pauseRequestedProcessIds.contains(state.processId)
              ? DownloadTaskStatus.paused
              : DownloadTaskStatus.cancelled,
        DownloadStateType.started => DownloadTaskStatus.downloading,
        DownloadStateType.unknown => DownloadTaskStatus.downloading,
      };

      if (existingTask.status == DownloadTaskStatus.completed) {
        return;
      }

      _upsertDownloadTask(
        existingTask.copyWith(
          status: status,
          errorMessage: status == DownloadTaskStatus.failed
              ? _fatalDownloadErrors[state.processId] ??
                    existingTask.errorMessage
              : null,
        ),
      );
    });

    _downloadErrorSubscription = _youtubeDL.onError.listen((error) {
      final existingTask = _downloadTaskById(error.processId);
      if (_pauseRequestedProcessIds.contains(error.processId) ||
          existingTask.status == DownloadTaskStatus.paused ||
          existingTask.status == DownloadTaskStatus.cancelled) {
        return;
      }

      final isFatalFailure = _looksLikeFatalDownloadFailure(error.error);
      final message = isFatalFailure
          ? _captureFatalDownloadError(error.processId, error.error)
          : error.error;

      if (isFatalFailure) {
        unawaited(_abortFailedDownload(error.processId));
      }

      _upsertDownloadTask(
        existingTask.copyWith(
          status: DownloadTaskStatus.failed,
          errorMessage: message,
          detailLog: _appendTaskLog(
            existingTask.detailLog,
            message,
            LogLevel.error,
          ),
        ),
      );
    });

    _downloadLogSubscription = _youtubeDL.onLog.listen((log) {
      final existingTask = _downloadTaskById(log.processId);
      final isTerminalFailure = _looksLikeFatalDownloadFailure(log.message);
      final message = isTerminalFailure
          ? _captureFatalDownloadError(log.processId, log.message)
          : log.message;
      final detailLog = _appendTaskLog(
        existingTask.detailLog,
        message,
        log.level,
      );

      if (isTerminalFailure &&
          existingTask.status != DownloadTaskStatus.failed &&
          existingTask.status != DownloadTaskStatus.completed &&
          existingTask.status != DownloadTaskStatus.cancelled) {
        unawaited(_abortFailedDownload(log.processId));
        _upsertDownloadTask(
          existingTask.copyWith(
            status: DownloadTaskStatus.failed,
            errorMessage: message,
            detailLog: detailLog,
          ),
        );
        return;
      }

      final metrics = _parseDownloadMetrics(log.message);

      _upsertDownloadTask(
        existingTask.copyWith(
          totalBytes: metrics.totalBytes ?? existingTask.totalBytes,
          downloadSpeedBytesPerSecond:
              metrics.speedBytesPerSecond ??
              existingTask.downloadSpeedBytesPerSecond,
          detailLog: detailLog,
        ),
      );
    });
  }

  DownloadRequest _buildAudioDownloadRequest({
    required String processId,
    required String url,
    required String fileName,
    required String outputDirectoryPath,
  }) {
    return DownloadRequest(
      url: url,
      outputPath: outputDirectoryPath,
      outputTemplate: '$fileName.%(ext)s',
      format: 'bestaudio[acodec!=none]/bestaudio/best',
      noPlaylist: true,
      extractAudio: true,
      audioFormat: 'mp3',
      audioQuality: 0,
      embedThumbnail: true,
      embedMetadata: true,
      customOptions: {
        '--write-thumbnail': '',
        '--convert-thumbnails': 'jpg',
        '--no-playlist': '',
        '--extractor-retries': '3',
      },
      processId: processId,
    );
  }

  Future<void> _initializeDownloader() async {
    if (kIsWeb) {
      _isDownloaderReady = false;
      _downloaderError = 'The downloader is unavailable on the web.';
      notifyListeners();
      return;
    }

    try {
      final initResult = await _youtubeDL.initialize(enableFFmpeg: true);
      _isDownloaderReady = initResult.success;
      _downloaderError = initResult.errorMessage;
    } catch (error) {
      _isDownloaderReady = false;
      _downloaderError =
          'The downloader is unavailable in this environment: $error';
    }
    notifyListeners();
  }

  Future<void> _ensureDownloaderReady() async {
    if (_isDownloaderReady) {
      return;
    }

    await _initializeDownloader();
    if (!_isDownloaderReady) {
      throw StateError(
        _downloaderError ?? 'The downloader could not be initialized.',
      );
    }
  }

  Future<DownloadResult> _runAudioDownloadWithRecovery({
    required DownloadRequest request,
    required DownloadPreview preview,
    required String processId,
  }) async {
    var result = await _youtubeDL.download(request);

    final fatalError = _fatalDownloadErrors[processId];
    if (fatalError != null) {
      return DownloadResult(
        status: OperationStatus.error,
        errorMessage: fatalError,
      );
    }

    final directError = result.errorMessage;
    if (_looksLikeFatalDownloadFailure(directError)) {
      final message = _captureFatalDownloadError(processId, directError!);
      return DownloadResult(
        status: OperationStatus.error,
        errorMessage: message,
      );
    }

    if (result.status == OperationStatus.success ||
        !_isYoutubeUrl(preview.url) ||
        !_looksLikeYoutubeExtractionFailure(
          result.errorMessage ?? _downloadTaskById(processId).detailLog,
        )) {
      return result;
    }

    final updated = await _refreshYoutubeDlBinary();
    if (!updated) {
      return result;
    }

    final task = _downloadTaskById(processId);
    _upsertDownloadTask(
      task.copyWith(
        detailLog: _appendTaskLog(
          task.detailLog,
          'Refreshing yt-dlp and retrying this YouTube download once.',
          LogLevel.warning,
        ),
      ),
    );

    result = await _youtubeDL.download(request);
    final retryFatalError = _fatalDownloadErrors[processId];
    if (retryFatalError != null) {
      return DownloadResult(
        status: OperationStatus.error,
        errorMessage: retryFatalError,
      );
    }
    return result;
  }

  Future<void> _abortFailedDownload(String processId) async {
    if (_pauseRequestedProcessIds.contains(processId)) {
      return;
    }

    try {
      await _youtubeDL.cancelDownload(processId);
    } catch (_) {
      // Ignore cancellation failures for already-terminating processes.
    }
  }

  Future<void> _cleanupIncompleteDownload(DownloadTaskInfo task) async {
    await _downloadStore.deleteArtifactsForBaseName(task.fileName);

    final matchingTracks = _downloadedTracks
        .where((track) {
          final filePath = track.filePath;
          if (filePath == null || filePath.trim().isEmpty) {
            return false;
          }

          final segments = Uri.file(filePath).pathSegments;
          final fileName = segments.isEmpty ? filePath : segments.last;
          return fileName.startsWith('${task.fileName}.');
        })
        .toList(growable: false);

    if (matchingTracks.isEmpty) {
      return;
    }

    final removedIds = matchingTracks.map((track) => track.id).toSet();
    final currentId = currentTrack?.id;
    final preferredTrackId =
        currentId == null || removedIds.contains(currentId) ? null : currentId;

    _downloadedTracks = _downloadedTracks
        .where((track) => !removedIds.contains(track.id))
        .toList(growable: false);
    await _downloadStore.saveTracks(_downloadedTracks);
    for (final track in matchingTracks) {
      _removeTrackFromPlaylists(track.id);
    }

    _rebuildTracks(preferredTrackId: preferredTrackId);
    await _syncSelectedTrack(autoplay: false);
  }

  void _removeTrackFromPlaylists(String trackId) {
    for (final trackIds in _playlistTrackIds.values) {
      trackIds.remove(trackId);
    }
  }

  Future<void> _activateTrackIndex(
    int index, {
    required bool openPlayer,
    required bool autoplay,
  }) async {
    if (index < 0 || index >= tracks.length) {
      return;
    }

    _selectedTrackIndex = index;
    _currentPosition = Duration.zero;
    positionListenable.value = Duration.zero;
    progress.value = 0;
    _currentTrackDuration = currentTrack?.duration ?? Duration.zero;
    if (openPlayer) {
      _isPlayerOpen = true;
    }
    notifyListeners();

    await _syncSelectedTrack(autoplay: autoplay);
  }

  Future<void> _syncSelectedTrack({required bool autoplay}) async {
    final track = currentTrack;

    if (track == null) {
      _isPlaying = false;
      _currentPosition = Duration.zero;
      _currentTrackDuration = Duration.zero;
      await _audioPlayer.stop();
      notifyListeners();
      return;
    }

    if (!track.canPlay) {
      _isPlaying = false;
      _currentPosition = Duration.zero;
      _currentTrackDuration = track.duration;
      await _audioPlayer.stop();
      notifyListeners();
      return;
    }

    try {
      // Smooth fade-out before loading new source
      if (_isPlaying) await _fadeVolume(to: 0);

      await _audioPlayer.setAudioSource(
        AudioSource.uri(
          Uri.file(track.filePath!),
          tag: _mediaItemForTrack(track),
        ),
      );
      _currentTrackDuration = _audioPlayer.duration ?? track.duration;

      final targetVolume = _normalizeAudio ? 0.84 : 1.0;
      if (autoplay) {
        await _audioPlayer.setVolume(0);
        await _audioPlayer.play();
        await _fadeVolume(to: targetVolume);
      } else {
        await _audioPlayer.setVolume(targetVolume);
        await _audioPlayer.pause();
      }
    } catch (error) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      try {
        await _audioPlayer.setAudioSource(
          AudioSource.uri(
            Uri.file(track.filePath!),
            tag: _mediaItemForTrack(track),
          ),
        );
        _currentTrackDuration = _audioPlayer.duration ?? track.duration;
        final targetVolume = _normalizeAudio ? 0.84 : 1.0;
        if (autoplay) {
          await _audioPlayer.setVolume(0);
          await _audioPlayer.play();
          await _fadeVolume(to: targetVolume);
        } else {
          await _audioPlayer.setVolume(targetVolume);
          await _audioPlayer.pause();
        }
      } catch (retryError) {
        _isPlaying = false;
        _libraryError = 'Unable to open ${track.title}: $retryError';
        notifyListeners();
      }
    }
  }

  MediaItem _mediaItemForTrack(Track track) {
    return MediaItem(
      id: track.id,
      album: track.album,
      title: track.title,
      artist: track.artist,
      genre: track.genre,
      duration: track.duration > Duration.zero ? track.duration : null,
      artUri: _artUriForTrack(track),
      extras: {
        'source': track.source.name,
        if (track.filePath != null) 'filePath': track.filePath,
      },
    );
  }

  Uri? _artUriForTrack(Track track) {
    final artworkFilePath = track.artworkFilePath;
    if (artworkFilePath != null && artworkFilePath.trim().isNotEmpty) {
      return Uri.file(artworkFilePath);
    }

    final artworkUrl = track.artworkUrl;
    if (artworkUrl != null && artworkUrl.trim().isNotEmpty) {
      return Uri.tryParse(artworkUrl);
    }

    return null;
  }

  void _persistResolvedCurrentTrackDuration(Duration duration) {
    final track = currentTrack;
    if (track == null || track.duration == duration) {
      return;
    }

    final updatedTrack = track.copyWith(duration: duration);
    _tracks = [
      for (var index = 0; index < _tracks.length; index++)
        if (index == _selectedTrackIndex) updatedTrack else _tracks[index],
    ];

    if (track.source == TrackSource.downloaded ||
        track.source == TrackSource.imported) {
      _downloadedTracks = _downloadedTracks
          .map(
            (candidate) => candidate.id == track.id ? updatedTrack : candidate,
          )
          .toList(growable: false);
      unawaited(_downloadStore.saveTracks(_downloadedTracks));
    }
  }

  Future<void> _handleTrackCompletion() async {
    if (_repeatMode == RepeatMode.one) {
      await _audioPlayer.seek(Duration.zero);
      await _audioPlayer.play();
      return;
    }

    final queue = _queueIndicesForNavigation();
    final currentQueueIndex = queue.indexOf(_selectedTrackIndex);
    final isLastTrack = currentQueueIndex == queue.length - 1;

    if (isLastTrack && _repeatMode == RepeatMode.off) {
      await _audioPlayer.pause();
      await _audioPlayer.seek(Duration.zero);
      return;
    }

    await _moveQueue(1, autoplay: true);
  }

  void _rebuildTracks({String? preferredTrackId}) {
    final nextTracks = [..._downloadedTracks, ..._deviceTracks];
    final oldTrackId =
        preferredTrackId ??
        (_tracks.isNotEmpty
            ? _tracks[_selectedTrackIndex.clamp(0, _tracks.length - 1)].id
            : null);

    _tracks = nextTracks;
    final preferredIndex = oldTrackId == null
        ? -1
        : _tracks.indexWhere((track) => track.id == oldTrackId);
    _selectedTrackIndex = preferredIndex == -1 ? 0 : preferredIndex;
  }

  DownloadTaskInfo _downloadTaskById(String processId) {
    return _downloadTasks.firstWhere(
      (task) => task.processId == processId,
      orElse: () => DownloadTaskInfo(
        processId: processId,
        url: '',
        title: 'Download',
        fileName: 'audio',
        status: DownloadTaskStatus.ready,
      ),
    );
  }

  void _upsertDownloadTask(DownloadTaskInfo task) {
    final nextTasks = [..._downloadTasks];
    final existingIndex = nextTasks.indexWhere(
      (candidate) => candidate.processId == task.processId,
    );

    if (existingIndex == -1) {
      nextTasks.insert(0, task);
    } else {
      nextTasks[existingIndex] = task;
    }

    _downloadTasks = nextTasks;
    notifyListeners();
  }

  int? _estimateDownloadSize(VideoInfo info) {
    final durationInSeconds = info.duration;
    if (durationInSeconds == null || durationInSeconds <= 0) {
      return null;
    }

    final audioFormats =
        (info.formats ?? const <VideoFormat?>[])
            .whereType<VideoFormat>()
            .where(
              (format) =>
                  format.acodec != null &&
                  format.acodec != 'none' &&
                  (format.tbr ?? 0) > 0,
            )
            .toList()
          ..sort((left, right) => (right.tbr ?? 0).compareTo(left.tbr ?? 0));

    final bitrateKbps = audioFormats.isEmpty ? null : audioFormats.first.tbr;
    if (bitrateKbps == null || bitrateKbps <= 0) {
      return null;
    }

    final totalBits = durationInSeconds * bitrateKbps * 1000;
    return (totalBits / 8).round();
  }

  bool _isYoutubeUrl(String rawUrl) {
    final host = Uri.tryParse(rawUrl)?.host.toLowerCase();
    if (host == null) {
      return false;
    }
    return host.contains('youtube.com') || host.contains('youtu.be');
  }

  bool _looksLikeYoutubeExtractionFailure(String? message) {
    if (message == null || message.trim().isEmpty) {
      return false;
    }

    final lower = message.toLowerCase();
    return lower.contains('sabr') ||
        lower.contains('missing a url') ||
        lower.contains('http error 403') ||
        lower.contains('unable to download video data');
  }

  bool _looksLikeFatalDownloadFailure(String? message) {
    if (message == null || message.trim().isEmpty) {
      return false;
    }

    final lower = message.toLowerCase();
    return lower.contains('403') ||
        lower.contains('forbidden') ||
        lower.contains('challenge request') ||
        lower.contains('sign in to confirm you') ||
        lower.contains('unable to get player script') ||
        lower.contains('error solving') ||
        lower.contains('preprocessing: conversion failed') ||
        lower.contains('postprocessing: conversion failed');
  }

  String _captureFatalDownloadError(String processId, String message) {
    return _fatalDownloadErrors.putIfAbsent(
      processId,
      () => _normalizeFatalDownloadMessage(message),
    );
  }

  String _normalizeFatalDownloadMessage(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('403') ||
        lower.contains('forbidden') ||
        lower.contains('challenge request') ||
        lower.contains('sign in to confirm you') ||
        lower.contains('unable to get player script') ||
        lower.contains('error solving')) {
      return 'The source blocked this download request (403 / anti-bot challenge), so Monolith stopped it before conversion.';
    }

    if (lower.contains('preprocessing: conversion failed') ||
        lower.contains('postprocessing: conversion failed')) {
      return 'Audio conversion failed, so Monolith stopped the download before saving anything to your library.';
    }

    return message.trim();
  }

  Future<bool> _refreshYoutubeDlBinary() async {
    if (_hasAttemptedYoutubeDlRefresh) {
      return false;
    }

    _hasAttemptedYoutubeDlRefresh = true;

    try {
      final updateResult = await _youtubeDL.updateYoutubeDL();
      return updateResult.status == OperationStatus.success;
    } catch (_) {
      return false;
    }
  }

  _ParsedDownloadMetrics _parseDownloadMetrics(String line) {
    final sizeMatch = RegExp(
      r'of\s+(?:~\s*)?([0-9]+(?:\.[0-9]+)?)\s*([KMGT]?i?B)',
      caseSensitive: false,
    ).firstMatch(line);
    final speedMatch = RegExp(
      r'at\s+([0-9]+(?:\.[0-9]+)?)\s*([KMGT]?i?B)/s',
      caseSensitive: false,
    ).firstMatch(line);

    return _ParsedDownloadMetrics(
      totalBytes: sizeMatch == null
          ? null
          : _parseByteCount(sizeMatch.group(1)!, sizeMatch.group(2)!),
      speedBytesPerSecond: speedMatch == null
          ? null
          : _parseByteCount(speedMatch.group(1)!, speedMatch.group(2)!),
    );
  }

  int? _parseByteCount(String rawValue, String rawUnit) {
    final value = double.tryParse(rawValue);
    if (value == null) {
      return null;
    }

    final unit = rawUnit.toUpperCase();
    const multipliers = <String, int>{
      'B': 1,
      'KB': 1000,
      'MB': 1000 * 1000,
      'GB': 1000 * 1000 * 1000,
      'TB': 1000 * 1000 * 1000 * 1000,
      'KIB': 1024,
      'MIB': 1024 * 1024,
      'GIB': 1024 * 1024 * 1024,
      'TIB': 1024 * 1024 * 1024 * 1024,
    };

    final multiplier = multipliers[unit];
    if (multiplier == null) {
      return null;
    }

    return (value * multiplier).round();
  }

  String? _appendTaskLog(String? existing, String line, LogLevel level) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      return existing;
    }

    final shouldKeep =
        level != LogLevel.info ||
        trimmed.contains('[download]') ||
        trimmed.contains('yt-dlp');
    if (!shouldKeep) {
      return existing;
    }

    final lines = [
      ...(existing?.split('\n').where((entry) => entry.trim().isNotEmpty) ??
          const <String>[]),
      trimmed,
    ];
    final collapsed = lines.length > 8
        ? lines.sublist(lines.length - 8)
        : lines;
    return collapsed.join('\n');
  }

  String _sanitizeFileName(String raw) {
    final compact = raw.replaceAll(RegExp(r'[<>:"/\\|?*]+'), ' ').trim();
    final normalized = compact.replaceAll(RegExp(r'\s+'), ' ');
    return normalized.isEmpty ? 'downloaded-audio' : normalized;
  }

  String _sanitizeImportedFileName(String raw) {
    final trimmed = raw.trim();
    final extensionIndex = trimmed.lastIndexOf('.');
    if (extensionIndex <= 0 || extensionIndex == trimmed.length - 1) {
      return _sanitizeFileName(trimmed);
    }

    final stem = _sanitizeFileName(trimmed.substring(0, extensionIndex));
    final extension = trimmed
        .substring(extensionIndex)
        .replaceAll(RegExp(r'[^A-Za-z0-9.]'), '')
        .toLowerCase();
    return '$stem$extension';
  }

  String _titleFromFileName(String fileName) {
    final extensionIndex = fileName.lastIndexOf('.');
    final stem = extensionIndex <= 0
        ? fileName
        : fileName.substring(0, extensionIndex);
    return stem.replaceAll(RegExp(r'[_-]+'), ' ');
  }

  @override
  void dispose() {
    positionListenable.dispose();
    progress.dispose();
    unawaited(_audioPlayer.dispose());
    _playerStateSubscription.cancel();
    _playerPositionSubscription.cancel();
    _playerDurationSubscription.cancel();
    _downloadProgressSubscription.cancel();
    _downloadStateSubscription.cancel();
    _downloadErrorSubscription.cancel();
    _downloadLogSubscription.cancel();
    _connectivitySubscription.cancel();
    _youtubeDL.dispose();
    super.dispose();
  }
}

class _ParsedDownloadMetrics {
  const _ParsedDownloadMetrics({this.totalBytes, this.speedBytesPerSecond});

  final int? totalBytes;
  final int? speedBytesPerSecond;
}
