import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:monolith/src/app/state/app_controller.dart';
import 'package:monolith/src/app/monolith_app.dart';
import 'package:monolith/src/core/models/music_models.dart';
import 'package:monolith/src/core/services/download_store.dart';
import 'package:monolith/src/core/services/local_media_service.dart';
import 'package:monolith/src/core/services/manual_audio_import_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Monolith opens on the downloads page', (tester) async {
    final controller = await _buildTestController();

    await tester.pumpWidget(MonolithApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('Downloads'), findsWidgets);
    expect(controller.currentTab, AppTab.downloads);
    expect(controller.selectedCategory, LibraryCategory.tracks);
    expect(controller.currentTrack?.title, 'Midnight Breeze');
    expect(controller.currentTrack?.artist, 'Luna Sol');
  });

  testWidgets('Downloads tab searches offline tracks', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(430, 1600);
    addTearDown(() => _resetSurface(tester));

    final controller = await _buildTestController(
      downloadedTracks: const [
        Track(
          id: 'download-zulu',
          title: 'Zulu Wave',
          artist: 'North Echo',
          album: 'Offline Cuts',
          genre: 'Electronic',
          duration: Duration(minutes: 3, seconds: 14),
          colors: [Color(0xFF9FE3D8), Color(0xFF0D6E6E), Color(0xFF18212F)],
          blurb: 'Saved for offline listening.',
          source: TrackSource.downloaded,
        ),
        Track(
          id: 'import-aurora',
          title: 'Aurora Bloom',
          artist: 'Glass Fields',
          album: 'Imports',
          genre: 'Ambient',
          duration: Duration(minutes: 4, seconds: 2),
          colors: [Color(0xFFB8F2E6), Color(0xFF145DA0), Color(0xFF0C1B2A)],
          blurb: 'Imported from Files.',
          source: TrackSource.imported,
        ),
      ],
    );

    await tester.pumpWidget(MonolithApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('downloads-search-field')),
      'Aurora',
    );
    await tester.pumpAndSettle();

    expect(find.text('Aurora Bloom'), findsOneWidget);
    expect(
      find.byKey(const Key('downloaded-track-download-zulu')),
      findsNothing,
    );
  });

  testWidgets('Mini deck opens the player overlay on a phone layout', (
    tester,
  ) async {
    await _setPhoneSurface(tester);
    addTearDown(() => _resetSurface(tester));

    final controller = await _buildTestController();

    await tester.pumpWidget(MonolithApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mini-player')), findsOneWidget);

    await tester.tap(find.byKey(const Key('mini-player')));
    await tester.pumpAndSettle();

    expect(controller.isPlayerOpen, isTrue);
    expect(find.byKey(const Key('player-overlay-sheet')), findsOneWidget);
    expect(find.byKey(const Key('player-deck')), findsOneWidget);
    expect(find.byKey(const Key('player-play-toggle')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Library narrow shell keeps the mini player flush to nav bar', (
    tester,
  ) async {
    await _setPhoneSurface(tester);
    addTearDown(() => _resetSurface(tester));

    final controller = await _buildTestController();

    await tester.pumpWidget(MonolithApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('nav-library-icon')));
    await tester.pumpAndSettle();

    expect(find.text('Library'), findsWidgets);
    expect(find.text('Tracks'), findsWidgets);
    expect(find.byKey(const Key('mini-player')), findsOneWidget);

    final miniPlayerRect = tester.getRect(find.byKey(const Key('mini-player')));
    final navRect = tester.getRect(find.byKey(const Key('bottom-nav')));

    expect(navRect.top - miniPlayerRect.bottom >= 6, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Search screen still shows the mini deck for player access', (
    tester,
  ) async {
    await _setPhoneSurface(tester);
    addTearDown(() => _resetSurface(tester));

    final controller = await _buildTestController();

    await tester.pumpWidget(MonolithApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('nav-search-icon')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mini-player')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Settings page updates controller preferences', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(430, 1400);
    addTearDown(() => _resetSurface(tester));

    final controller = await _buildTestController();

    await tester.pumpWidget(MonolithApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('nav-library-icon')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('settings-button')));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsWidgets);

    await tester.tap(find.text('Dark').last);
    await tester.pumpAndSettle();
    expect(controller.themePreference, ThemePreference.dark);

    await tester.tap(find.byKey(const Key('normalize-audio-switch')));
    await tester.pumpAndSettle();
    expect(controller.normalizeAudio, isFalse);
  });

  testWidgets('Search filters tracks and opens matching result', (
    tester,
  ) async {
    final controller = await _buildTestController();

    await tester.pumpWidget(MonolithApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('nav-search-icon')));
    await tester.pumpAndSettle();

    controller.setSearchQuery('Luna');
    await tester.pump();

    expect(controller.currentTab, AppTab.search);
    expect(controller.searchResults, hasLength(1));
    expect(controller.searchResults.single.title, 'Midnight Breeze');

    controller.selectTrack(
      controller.searchResults.single,
      openPlayer: true,
      autoplay: false,
    );
    await tester.pumpAndSettle();

    expect(controller.currentTab, AppTab.search);
    expect(controller.isPlayerOpen, isTrue);
    expect(find.byKey(const Key('player-overlay-sheet')), findsOneWidget);
    expect(controller.currentTrack?.title, 'Midnight Breeze');
    expect(controller.currentTrack?.artist, 'Luna Sol');
  });

  test('Controller imports audio files into the offline library', () async {
    final controller = MonolithController(
      localMediaService: _FakeLocalMediaService(_sampleTracks),
      downloadStore: _FakeDownloadStore(const []),
      manualAudioImportService: _FakeManualAudioImportService([
        ImportedAudioFile(
          name: 'night-drive.mp3',
          bytes: Uint8List.fromList([0, 1, 2, 3]),
        ),
      ]),
    );

    await controller.refreshLibrary();
    final message = await controller.importAudioFiles();

    expect(message, 'Imported 1 audio file from Files.');
    expect(
      controller.tracks.any(
        (track) =>
            track.source == TrackSource.imported &&
            track.title == 'night drive' &&
            track.canPlay,
      ),
      isTrue,
    );
  });
}

Future<void> _setPhoneSurface(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(375, 812);
  await tester.pump();
}

Future<void> _resetSurface(WidgetTester tester) async {
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
  await tester.pump();
}

Future<MonolithController> _buildTestController({
  List<Track> downloadedTracks = const [],
}) async {
  final controller = MonolithController(
    localMediaService: _FakeLocalMediaService(_sampleTracks),
    downloadStore: _FakeDownloadStore(downloadedTracks),
  );

  await controller.refreshLibrary();
  return controller;
}

const _sampleTracks = [
  Track(
    id: 'track-luna',
    title: 'Midnight Breeze',
    artist: 'Luna Sol',
    album: 'Mock Album',
    genre: 'Ambient',
    duration: Duration(minutes: 4, seconds: 12),
    colors: [Color(0xFFB8F2E6), Color(0xFF0D6E6E), Color(0xFF18212F)],
    blurb: 'Breathing-room ambience with a polished studio sheen.',
    source: TrackSource.device,
  ),
  Track(
    id: 'track-aether',
    title: 'Weightless Dreams',
    artist: 'Aether Velocity',
    album: 'Mock Album',
    genre: 'Electronic',
    duration: Duration(minutes: 3, seconds: 45),
    colors: [Color(0xFF5CE1D8), Color(0xFF145DA0), Color(0xFF0C1B2A)],
    blurb: 'Low-gravity synthwork for late-night focus windows.',
    source: TrackSource.device,
  ),
];

class _FakeLocalMediaService extends LocalMediaService {
  _FakeLocalMediaService(this._tracks);

  final List<Track> _tracks;

  @override
  Future<LocalMediaSnapshot> loadTracks({
    bool retryRequest = false,
    bool requestPermission = true,
  }) async {
    return LocalMediaSnapshot(permissionGranted: true, tracks: _tracks);
  }

  @override
  Future<void> scanMedia(String path) async {}
}

class _FakeDownloadStore extends DownloadStore {
  _FakeDownloadStore(this._tracks)
    : _directory = Directory.systemTemp.createTempSync('monolith_test_');

  final Directory _directory;
  List<Track> _tracks;

  @override
  Future<Directory> getDownloadDirectory() async {
    return _directory;
  }

  @override
  Future<List<Track>> loadTracks() async {
    return _tracks;
  }

  @override
  Future<void> saveTracks(List<Track> tracks) async {
    _tracks = tracks;
  }

  @override
  Future<File> saveImportedAudio({
    required String preferredFileName,
    String? sourcePath,
    Uint8List? bytes,
  }) async {
    final file = File(
      '${_directory.path}${Platform.pathSeparator}$preferredFileName',
    );
    if (sourcePath != null && sourcePath.trim().isNotEmpty) {
      return File(sourcePath).copy(file.path);
    }

    await file.writeAsBytes(bytes!, flush: true);
    return file;
  }

  @override
  Future<String?> findArtworkForAudio(String audioFilePath) async {
    return null;
  }
}

class _FakeManualAudioImportService extends ManualAudioImportService {
  _FakeManualAudioImportService(this._files);

  final List<ImportedAudioFile> _files;

  @override
  Future<List<ImportedAudioFile>> pickAudioFiles() async {
    return _files;
  }
}
