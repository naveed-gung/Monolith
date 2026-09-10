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

  test('corrupt manifest still recovers surviving audio files', () async {
    final music = await store.getDownloadDirectory();
    File('${music.path}/survives.mp3').writeAsBytesSync([1, 2, 3]);
    File(
      '${music.parent.path}/manifest.json',
    ).writeAsStringSync('{"tracks": [');
    final tracks = await store.loadTracksMergingDisk();
    expect(tracks, hasLength(1));
  });

  for (final ext in ['aiff', 'alac', 'amr', 'oga', 'weba']) {
    test('accepted $ext imports can be recovered without manifest', () async {
      final music = await store.getDownloadDirectory();
      File('${music.path}/recovered.$ext').writeAsBytesSync([1, 2, 3]);
      final tracks = await store.loadTracksMergingDisk();
      expect(tracks, hasLength(1));
    });
  }

  test('invalid manifest shape does not block disk recovery', () async {
    final music = await store.getDownloadDirectory();
    File('${music.path}/survives.mp3').writeAsBytesSync([1, 2, 3]);
    final manifest = File('${music.parent.path}/manifest.json');
    manifest.writeAsStringSync('{"tracks":null}');
    expect(await store.loadTracksMergingDisk(), hasLength(1));
    expect(
      music.parent.listSync().where((f) => f.path.contains('.corrupt-')),
      isNotEmpty,
    );
  });

  test(
    'one malformed entry does not discard valid playlist track IDs',
    () async {
      final music = await store.getDownloadDirectory();
      final file = File('${music.path}/valid.mp3')..writeAsBytesSync([1, 2, 3]);
      final track = Track(
        id: 'stable-id',
        title: 'Valid',
        artist: 'Artist',
        album: 'Album',
        genre: '',
        duration: Duration.zero,
        colors: Track.paletteForSeed('valid'),
        blurb: '',
        source: TrackSource.imported,
        filePath: file.path,
      );
      File('${music.parent.path}/manifest.json').writeAsStringSync(
        jsonEncode([
          track.toJson(),
          {'id': 42},
        ]),
      );
      final tracks = await store.loadTracksMergingDisk();
      expect(tracks.single.id, 'stable-id');
      expect(
        music.parent.listSync().where((f) => f.path.contains('.corrupt-')),
        isNotEmpty,
      );
    },
  );
}
