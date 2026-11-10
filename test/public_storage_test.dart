import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:monolith/src/core/models/music_models.dart';
import 'package:monolith/src/core/services/download_store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Routes path_provider to a temp dir so DownloadStore can run in a unit
/// test; `DownloadStore(android: true, publicMusicDir: …)` fakes the rest.
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
  @override
  Future<String?> getExternalStoragePath() async => '$root/external';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late Directory pub; // stands in for /sdcard/Music/Monolith
  late DownloadStore store;

  String privateRoot() => '${tmp.path}/external/Monolith';

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pubstore_test');
    pub = Directory('${tmp.path}/sdcard/Music/Monolith');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    store = DownloadStore(android: true, publicMusicDir: pub.path);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Track seedTrack(String id, String filePath, {String? art}) => Track(
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
    artworkFilePath: art,
  );

  test('audio lands in the public root while manifest stays private', () async {
    final music = await store.getDownloadDirectory();
    expect(music.path, '${pub.path}/Music');
    expect(await store.audioStorageIsPublic(), isTrue);

    final audio = File('${music.path}/song.m4a')..writeAsBytesSync([1, 2, 3]);
    await store.saveTracks([seedTrack('t1', audio.path)]);

    // Manifest sits under the private root, not the public one.
    final manifest = File('${privateRoot()}/manifest.json');
    expect(await manifest.exists(), isTrue);
    expect(await File('${privateRoot()}/Music/song.m4a').exists(), isFalse);
  });

  test('private fallback keeps everything under the private root', () async {
    store = DownloadStore(android: true);
    final music = await store.getDownloadDirectory();
    expect(music.path, '${privateRoot()}/Music');
    expect(await store.audioStorageIsPublic(), isFalse);
  });

  test('migration moves audio to public, artwork to Art, rewrites paths',
      () async {
    // Seed a pre-1.5.1 private layout: audio + artwork sidecar + manifest.
    final legacyMusic = Directory('${privateRoot()}/Music')
      ..createSync(recursive: true);
    final legacyAudio = File('${legacyMusic.path}/old.m4a')
      ..writeAsBytesSync([9, 9, 9]);
    File('${legacyMusic.path}/old.jpg').writeAsBytesSync([7]);
    final legacyStore = DownloadStore(android: true);
    await legacyStore.saveTracks([
      seedTrack('old', legacyAudio.path, art: '${legacyMusic.path}/old.jpg'),
    ]);

    await store.loadTracksMergingDisk();

    // Audio moved to public Music with its relative layout intact.
    final moved = File('${pub.path}/Music/old.m4a');
    expect(await moved.exists(), isTrue);
    expect(await moved.length(), 3);
    expect(await legacyAudio.exists(), isFalse);
    // Artwork moved to the private Art folder, keyed by stem.
    expect(await File('${privateRoot()}/Art/old.jpg').exists(), isTrue);
    // Manifest path rewritten to the public file.
    final tracks = await store.loadTracks();
    expect(tracks.single.filePath, moved.path);
    expect(tracks.single.artworkFilePath, '${privateRoot()}/Art/old.jpg');
    // Idempotent: second run changes nothing.
    await store.loadTracksMergingDisk();
    expect((await store.loadTracks()).single.filePath, moved.path);
  });

  test('migration preserves the Imports subfolder layout', () async {
    final imports = Directory('${privateRoot()}/Music/Imports')
      ..createSync(recursive: true);
    File('${imports.path}/picked.mp3').writeAsBytesSync([4]);

    await store.loadTracksMergingDisk();

    final moved = File('${pub.path}/Music/Imports/picked.mp3');
    expect(await moved.exists(), isTrue);
    final tracks = await store.loadTracks();
    expect(
      tracks.single.filePath!.replaceAll('\\', '/'),
      moved.path.replaceAll('\\', '/'),
    );
    expect(tracks.single.source, TrackSource.imported);
  });

  test('failed copy keeps the private original', () async {
    final legacyMusic = Directory('${privateRoot()}/Music')
      ..createSync(recursive: true);
    final legacyAudio = File('${legacyMusic.path}/stuck.m4a')
      ..writeAsBytesSync([1, 2]);
    // A mismatched-length file at the target forces the verify to fail.
    final target = File('${pub.path}/Music/stuck.m4a')
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3, 4]);
    await store.loadTracksMergingDisk();
    expect(await legacyAudio.exists(), isTrue);
    expect(await target.length(), 4);
  });

  test('artwork lookup prefers sidecar then private Art dir', () async {
    final music = await store.getDownloadDirectory()..create(recursive: true);
    final audio = File('${music.path}/a.m4a')..writeAsBytesSync([1]);
    File('${music.path}/a.png').writeAsBytesSync([1]);
    expect(await store.findArtworkForAudio(audio.path), '${music.path}/a.png');
    await File('${music.path}/a.png').delete();

    final artDir = Directory('${privateRoot()}/Art')..createSync(recursive: true);
    File('${artDir.path}/a.webp').writeAsBytesSync([1]);
    expect(
      await store.findArtworkForAudio(audio.path),
      '${artDir.path}/a.webp',
    );
  });

  test('resolves stale private paths under the public root', () async {
    final music = await store.getDownloadDirectory()..create(recursive: true);
    final audio = File('${music.path}/here.m4a')..writeAsBytesSync([1]);
    final stale = '${privateRoot()}/Music/here.m4a';
    expect(await store.resolveTrackPath(stale), audio.path);
  });
}
