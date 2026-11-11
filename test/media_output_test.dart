import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:monolith/src/core/services/media_output.dart';

/// Guards the scoped-storage contract: only finished audio may land in the
/// public Music folder — `.part`/staged files stay private, artwork goes to
/// the private Art directory.
void main() {
  late Directory tempRoot;
  late Directory staging;
  late Directory publicMusic;
  late Directory artDir;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('media_output_test_');
    staging = await Directory('${tempRoot.path}/staging').create();
    publicMusic = await Directory('${tempRoot.path}/Music/Monolith/Music')
        .create(recursive: true);
    artDir = await Directory('${tempRoot.path}/Art').create(recursive: true);
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  Future<List<String>> namesIn(Directory dir) async {
    final entities = await dir.list().toList();
    return entities.map((e) => e.path.split(RegExp(r'[/\\]')).last).toList()
      ..sort();
  }

  test('commit publishes staged audio under its final name only', () async {
    final stagedFile = File('${staging.path}/audio.part')
      ..writeAsBytesSync(List<int>.filled(64, 7));
    final target = File('${publicMusic.path}/song-abc123.mp3');

    await commitStagedAudio(staged: stagedFile, target: target);

    expect(await target.exists(), isTrue);
    expect(await target.length(), 64);
    expect(await stagedFile.exists(), isFalse);
    // Nothing but the finished audio file may appear in public Music.
    expect(await namesIn(publicMusic), <String>['song-abc123.mp3']);
  });

  test('commit failure leaves no partial target behind', () async {
    final missing = File('${staging.path}/gone.part');
    final target = File('${publicMusic.path}/song-x.mp3');

    await expectLater(
      commitStagedAudio(staged: missing, target: target),
      throwsA(anything),
    );
    expect(await target.exists(), isFalse);
    expect(await namesIn(publicMusic), isEmpty);
  });

  test('artwork resolves into the private Art dir when provided', () {
    final path = artworkPathForAudio(
      '${publicMusic.path}/Song Title.mp3',
      artworkDirectory: artDir.path,
    );
    expect(
      path,
      '${artDir.path}${Platform.pathSeparator}Song Title.jpg',
    );
    expect(path.startsWith(publicMusic.path), isFalse);
  });

  test('artwork falls back to a sidecar beside audio without an art dir', () {
    final path = artworkPathForAudio('${publicMusic.path}/song.m4a');
    expect(
      path.replaceAll('\\', '/'),
      '${publicMusic.path.replaceAll('\\', '/')}/song.jpg',
    );
  });
}
