import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:monolith/src/app/state/app_controller.dart';
import 'package:monolith/src/app/monolith_app.dart';
import 'package:monolith/src/core/models/music_models.dart';
import 'package:monolith/src/core/services/download_store.dart';
import 'package:monolith/src/core/services/local_media_service.dart';

import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:monolith/src/features/settings/presentation/settings_page.dart';
import 'package:monolith/src/features/storage/presentation/storage_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Platform-plugin stubs: no real plugins exist under the test binding, and
  // unhandled MissingPluginExceptions from controller bootstrap would fail
  // every test.
  SharedPreferences.setMockInitialValues({});
  TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
        (call) async => null,
      );
  TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/connectivity'),
        (call) async => <String>['none'],
      );

  final results = <Map<String, Object?>>[];
  testWidgets('Android back closes the full player before leaving the app', (
    tester,
  ) async {
    final controller = await _buildTestController(tester);
    try {
      await tester.pumpWidget(MonolithApp(controller: controller));
      await tester.pumpAndSettle();
      controller.openPlayer();
      await tester.pumpAndSettle();
      expect(controller.isPlayerOpen, isTrue);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(controller.isPlayerOpen, isFalse);
    } finally {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    }
  });
  for (final count in [0, 1]) {
    testWidgets('Storage reports actual export result: $count saved', (
      tester,
    ) async {
      final controller = await _buildTestController(
        tester,
        downloadedTracks: [
          _sampleTracks.first.copyWith(
            source: TrackSource.downloaded,
            filePath: '/audit.mp3',
          ),
        ],
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('monolith/media_import'),
        (call) async {
          if (call.method == 'exportToSaf') {
            return {'savedCount': count, 'canceled': false};
          }
          return null;
        },
      );
      try {
        await tester.pumpWidget(MonolithApp(controller: controller));
        await tester.pumpAndSettle();
        final navigator = tester.state<NavigatorState>(
          find.byType(Navigator).first,
        );
        unawaited(
          navigator.push(
            MaterialPageRoute<void>(builder: (_) => const StoragePage()),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byTooltip('Save to Files'));
        await tester.tap(find.byTooltip('Save to Files'));
        await tester.pumpAndSettle();
        expect(
          find.text(
            count == 1
                ? 'Saved to your chosen folder.'
                : 'Could not export this file. Check available space and folder access, then try again.',
          ),
          findsOneWidget,
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        messenger.setMockMethodCallHandler(
          const MethodChannel('monolith/media_import'),
          null,
        );
      }
    });
  }
  setUpAll(() async {
    await Directory('artifacts/verification').create(recursive: true);
    final config =
        jsonDecode(await File('.dart_tool/package_config.json').readAsString())
            as Map;
    final flutter = (config['packages'] as List).firstWhere(
      (p) => p['name'] == 'flutter',
    );
    final flutterRoot = Directory.fromUri(
      File(
        '.dart_tool/package_config.json',
      ).absolute.uri.resolve(flutter['rootUri'] as String),
    ).parent.parent.uri;
    // Replace Flutter test's block-shaped Ahem font with real Roboto metrics.
    // Also load shipped icon fonts so screenshots show the actual controls.
    for (final family in ['Roboto', 'Ahem']) {
      final loader = FontLoader(family);
      for (final weight in ['regular', 'medium', 'bold']) {
        loader.addFont(
          File.fromUri(
            flutterRoot.resolve(
              'bin/cache/artifacts/material_fonts/roboto-$weight.ttf',
            ),
          ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
        );
      }
      await loader.load();
    }
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in manifest) {
      final loader = FontLoader(entry['family'] as String);
      for (final font in entry['fonts'] as List) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
  });
  tearDownAll(() async {
    if (results.isEmpty) return;
    await File(
      'artifacts/verification/ui-results.json',
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(results));
  });
  for (final spec in [
    ('phone', const Size(375, 812), 1.0),
    ('small', const Size(320, 568), 1.0),
    ('large-text', const Size(375, 812), 2.0),
    ('landscape', const Size(812, 375), 1.0),
    ('tablet', const Size(1024, 768), 1.0),
  ]) {
    for (final page in [
      'library',
      'downloads',
      'songs',
      'search',
      'player',
      'settings',
      'storage',
    ]) {
      testWidgets('${spec.$1} $page', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = spec.$2;
        tester.platformDispatcher.textScaleFactorTestValue = spec.$3;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final controller = await _buildTestController(tester);
        final errors = <String>[];
        final original = FlutterError.onError;
        FlutterError.onError = (details) {
          errors.add(details.exceptionAsString());
        };
        final captureKey = GlobalKey();
        try {
          await tester.pumpWidget(
            RepaintBoundary(
              key: captureKey,
              child: MonolithApp(controller: controller),
            ),
          );
          await tester.pumpAndSettle();
          if (page != 'library') errors.clear();
          if (page == 'player') {
            controller.openPlayer();
          } else if (page == 'settings' || page == 'storage') {
            final navigator = tester.state<NavigatorState>(
              find.byType(Navigator).first,
            );
            unawaited(
              navigator.push(
                MaterialPageRoute<void>(
                  builder: (_) => page == 'settings'
                      ? const SettingsPage()
                      : const StoragePage(),
                ),
              ),
            );
          } else {
            controller.selectTab(AppTab.values.byName(page));
          }
          await tester.pumpAndSettle();
          final navVisible = find
              .byKey(const Key('nav-search-icon'))
              .evaluate()
              .isNotEmpty;
          final boundary =
              captureKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final shot = await boundary.toImage(pixelRatio: 1);
            final bytes = await shot.toByteData(format: ui.ImageByteFormat.png);
            await File(
              'artifacts/verification/${spec.$1}-$page.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            shot.dispose();
          });
          results.add({
            'surface': spec.$1,
            'page': page,
            'errors': errors.toSet().toList(),
            'navigationVisible': navVisible,
          });
          if (['library', 'downloads', 'songs', 'search'].contains(page)) {
            expect(
              navVisible,
              isTrue,
              reason: 'Every main surface needs visible navigation',
            );
          }
        } finally {
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
          FlutterError.onError = original;
        }
        expect(errors, isEmpty, reason: '${spec.$1} $page');
      });
    }
  }
}

Future<MonolithController> _buildTestController(
  WidgetTester tester, {
  List<Track> downloadedTracks = const [],
}) async {
  // DownloadStore.loadTracksMergingDisk() streams real filesystem I/O
  // (Directory.list), which never completes inside the FakeAsync zone that
  // wraps testWidgets bodies. runAsync lifts the bootstrap onto the real
  // event loop so the disk scan can finish.
  final controller = await tester.runAsync(() async {
    final store = _FakeDownloadStore(downloadedTracks);
    addTearDown(() async {
      if (await store._directory.exists()) {
        await store._directory.delete(recursive: true);
      }
    });
    final fresh = MonolithController(
      localMediaService: _FakeLocalMediaService(_sampleTracks),
      downloadStore: store,
    );

    await fresh.whenReady;
    return fresh;
  });
  return controller!;
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
