import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:monolith/src/core/services/lyrics_service.dart';

/// TASK C — lyrics must never block or fail a download.
///
/// Two guarantees are asserted here:
///   1. Lyrics resolve to a clean *empty state* (null) when no sidecar exists,
///      so the player shows "No lyrics" rather than erroring or spinning.
///   2. The download path in `app_controller.dart` has ZERO lyric dependency —
///      a source guard so a future change can't quietly wire lyrics fetching
///      into the download and make audio downloads depend on it.
void main() {
  group('LyricsService empty state', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('lyrics_test');
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('returns null when no .lrc sidecar is present (empty state)', () async {
      final audio = File('${tmp.path}/song.mp3');
      await audio.writeAsBytes([0, 1, 2, 3]);

      final lyrics = await const LyricsService().loadForAudio(audio.path);

      expect(lyrics, isNull, reason: 'no sidecar -> empty state, not an error');
    });

    test('loads parsed lines when a .lrc sidecar exists', () async {
      final audio = File('${tmp.path}/song.mp3');
      await audio.writeAsBytes([0, 1, 2, 3]);
      await File('${tmp.path}/song.lrc')
          .writeAsString('[00:01.00]hello\n[00:02.50]world\n');

      final lyrics = await const LyricsService().loadForAudio(audio.path);

      expect(lyrics, isNotNull);
      expect(lyrics!.length, 2);
      expect(lyrics.first.text, 'hello');
      expect(lyrics.first.time, const Duration(seconds: 1));
    });
  });

  test('download path in app_controller has no lyric dependency', () {
    final source =
        File('lib/src/app/state/app_controller.dart').readAsStringSync();

    // Isolate the managed-download method body.
    final start = source.indexOf('Future<void> _startManagedDownload(');
    expect(start, isNonNegative, reason: '_startManagedDownload must exist');
    // Next top-level method after it begins the downloader binding region.
    final end = source.indexOf('void _bindDownloader()', start);
    expect(end, greaterThan(start));

    final body = source.substring(start, end).toLowerCase();
    // The word "lyric" may only appear inside the INVARIANT comment block, never
    // as a call. Strip comment lines, then assert no lyric token remains.
    final code = body
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    expect(
      code.contains('lyric'),
      isFalse,
      reason: 'lyrics must not be fetched/wired into the download path',
    );
  });
}
