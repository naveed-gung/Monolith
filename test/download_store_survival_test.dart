import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:monolith/src/core/models/music_models.dart';
import 'package:monolith/src/core/services/download_store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Routes path_provider to a temp dir so DownloadStore can run in a unit test.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getTemporaryPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late DownloadStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('dlstore_test');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    store = DownloadStore();
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Track seedTrack(String id, String filePath) => Track(
        id: id,
        title: id,
        artist: 'A',
        album: 'Downloads',
        genre: 'g',
        duration: Duration.zero,
        colors: Track.paletteForSeed(id),
        blurb: '',
        source: TrackSource.downloaded,
        filePath: filePath,
      );

  group('D1 — update keeps downloads', () {
    test('seeded manifest + files survive a fresh boot, new download prepends',
        () async {
      final musicDir = await store.getDownloadDirectory();
      final a = File('${musicDir.path}/old.mp3')..writeAsBytesSync([1]);
      await store.saveTracks([seedTrack('old', a.path)]);

      // Fresh boot: a new store reads the existing manifest.
      final booted = await DownloadStore().loadTracks();
      expect(booted.map((t) => t.id), ['old']);

      // A new download prepends (newest-first), old one kept.
      final b = File('${musicDir.path}/new.mp3')..writeAsBytesSync([1]);
      final next = [seedTrack('new', b.path), ...booted];
      await store.saveTracks(next);

      final reloaded = await DownloadStore().loadTracks();
      expect(reloaded.map((t) => t.id), ['new', 'old']);
    });

    test('manifest entries whose file is gone are pruned on load', () async {
      final musicDir = await store.getDownloadDirectory();
      final present = File('${musicDir.path}/here.mp3')..writeAsBytesSync([1]);
      await store.saveTracks([
        seedTrack('here', present.path),
        seedTrack('gone', '${musicDir.path}/missing.mp3'),
      ]);

      final loaded = await store.loadTracks();
      expect(loaded.map((t) => t.id), ['here']);
    });
  });

  group('D2 — repopulate from surviving files on disk', () {
    test('audio files not in the manifest are re-added on merge', () async {
      final musicDir = await store.getDownloadDirectory();
      // A tracked file (in manifest) + two orphan files only on disk.
      final tracked = File('${musicDir.path}/tracked.mp3')
        ..writeAsBytesSync([1]);
      await store.saveTracks([seedTrack('tracked', tracked.path)]);
      File('${musicDir.path}/orphan1.m4a').writeAsBytesSync([1]);
      File('${musicDir.path}/orphan2.flac').writeAsBytesSync([1]);
      // A non-audio file must be ignored.
      File('${musicDir.path}/cover.jpg').writeAsBytesSync([1]);

      final merged = await store.loadTracksMergingDisk();
      final paths =
          merged.map((t) => t.filePath!.split(RegExp(r'[\\/]')).last).toSet();
      expect(paths, containsAll(['tracked.mp3', 'orphan1.m4a', 'orphan2.flac']));
      expect(paths.contains('cover.jpg'), isFalse);

      // Orphans are now persisted as manifest entries.
      final raw = File('${(await store.getDownloadDirectory()).parent.path}'
              '/manifest.json')
          .readAsStringSync();
      expect((jsonDecode(raw) as List).length, 3);
    });

    test('rescan with no orphans returns the manifest unchanged', () async {
      final musicDir = await store.getDownloadDirectory();
      final f = File('${musicDir.path}/only.mp3')..writeAsBytesSync([1]);
      await store.saveTracks([seedTrack('only', f.path)]);

      final merged = await store.loadTracksMergingDisk();
      expect(merged.length, 1);
      expect(merged.single.id, 'only');
    });
  });
}
