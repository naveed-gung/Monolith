import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:monolith/data/repositories/playback_repository.dart';
import 'package:monolith/data/services/audio/playback_engine.dart';
import 'package:monolith/data/services/storage/library_store.dart';
import 'package:monolith/domain/models/enums.dart';
import 'package:monolith/domain/models/track.dart';

/// Scriptable [PlaybackEngine] — no audio backend, just recorded calls and
/// controllable streams so queue/repeat/shuffle logic can be tested in
/// isolation.
class FakeEngine implements PlaybackEngine {
  final _playingController = StreamController<bool>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration?>.broadcast();
  final _completionController = StreamController<void>.broadcast();

  /// Every loadTrack call as `(track, autoplay)` pairs, in order.
  final List<(Track, bool)> loadedTracks = [];
  int seekToZeroCount = 0;
  double? lastVolume;
  double? lastSpeed;

  bool _playing = false;
  Duration _position = Duration.zero;
  Duration? _duration;

  @override
  bool get playing => _playing;
  set playing(bool value) {
    _playing = value;
    _playingController.add(value);
  }

  @override
  Duration get position => _position;
  set position(Duration value) {
    _position = value;
    _positionController.add(value);
  }

  @override
  Duration? get duration => _duration;

  @override
  Stream<bool> get playingStream => _playingController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration?> get durationStream => _durationController.stream;

  @override
  Stream<void> get completionStream => _completionController.stream;

  @override
  Future<void> loadTrack(Track track, {bool autoplay = true}) async {
    loadedTracks.add((track, autoplay));
    _playing = autoplay;
    _position = Duration.zero;
    _duration = track.durationMs > 0
        ? Duration(milliseconds: track.durationMs)
        : null;
    _durationController.add(_duration);
    _playingController.add(_playing);
  }

  @override
  Future<void> play() async => playing = true;

  @override
  Future<void> pause() async => playing = false;

  @override
  Future<void> seek(Duration newPosition) async {
    if (newPosition == Duration.zero) seekToZeroCount++;
    position = newPosition;
  }

  @override
  Future<void> setVolume(double volume) async => lastVolume = volume;

  @override
  Future<void> setSpeed(double speed) async => lastSpeed = speed;

  @override
  Future<void> applyNormalization(bool enabled) async {}

  @override
  Future<void> fadeTo(double volume, {int ms = 220}) async {}

  /// Simulates the track playing through to the end.
  void emitCompletion() => _completionController.add(null);

  @override
  void dispose() {
    _playingController.close();
    _positionController.close();
    _durationController.close();
    _completionController.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory fixtureRoot;
  late FakeEngine engine;
  late LibraryStore store;
  late PlaybackRepository repo;

  setUp(() async {
    fixtureRoot = await Directory.systemTemp.createTemp('mono_p3_playback');
    engine = FakeEngine();
    store = LibraryStore(
      rootDirFactory: () async => Directory('${fixtureRoot.path}/root'),
    );
    repo = PlaybackRepository(engine: engine, libraryStore: store);
  });

  tearDown(() async {
    await repo.close();
    engine.dispose();
    try {
      await fixtureRoot.delete(recursive: true);
    } on FileSystemException catch (_) {
      // Best-effort cleanup.
    }
  });

  /// Creates a real (non-empty) audio file so [LibraryStore.load] does not
  /// prune the entry during play-count assertions.
  Future<Track> realTrack(String id, String title) async {
    final musicDir = await store.musicDirectory();
    final file = File('${musicDir.path}/$title.mp3')
      ..writeAsBytesSync(List.filled(16, id.hashCode & 0xFF));
    return Track(
      id: id,
      title: title,
      artist: 'Artist $id',
      durationMs: 60000,
      filePath: file.path,
      addedAt: DateTime(2026, 1, 1),
    );
  }

  /// Runs microtasks until [condition] holds (completion events flow through
  /// stream listeners plus file IO, so a few event-loop turns are needed).
  Future<void> pumpUntil(bool Function() condition) async {
    for (var i = 0; i < 500; i++) {
      if (condition()) return;
      await Future<void>.delayed(Duration.zero);
    }
    fail('Condition not met within 500 event-loop turns');
  }

  group('shuffle', () {
    test(
      'produces a stable permutation that visits every track once',
      () async {
        final tracks = [
          for (var i = 0; i < 5; i++) await realTrack('t$i', 'Song $i'),
        ];
        await repo.playQueue(tracks, startIndex: 2);
        expect(repo.currentIndex.value, 2);

        repo.setShuffleEnabled(true);

        final order = repo.playOrder;
        expect(order, hasLength(5));
        expect(
          order.toSet(),
          equals({0, 1, 2, 3, 4}),
          reason: 'permutation must contain every index exactly once',
        );
        expect(
          order.first,
          2,
          reason: 'the current track stays pinned first for seamless shuffle',
        );

        // Advancing must follow the SAME stored permutation — no reshuffling
        // per skip — and visit each remaining track exactly once before wrap.
        final visited = <int>{repo.currentIndex.value};
        for (var step = 0; step < 4; step++) {
          await repo.next();
          visited.add(repo.currentIndex.value);
          expect(
            repo.playOrder,
            order,
            reason: 'order must not change between advances',
          );
        }
        expect(visited, equals({0, 1, 2, 3, 4}));

        // One more next wraps to the pinned start of the order.
        await repo.next();
        expect(repo.currentIndex.value, order.first);
      },
    );

    test(
      'toggling off restores identity order and keeps the current track',
      () async {
        final tracks = [
          for (var i = 0; i < 4; i++) await realTrack('t$i', 'Song $i'),
        ];
        await repo.playQueue(tracks, startIndex: 1);
        repo.setShuffleEnabled(true);
        await repo.next(); // move somewhere else

        final currentBefore = repo.currentIndex.value;
        repo.setShuffleEnabled(false);

        expect(repo.playOrder, [0, 1, 2, 3]);
        expect(repo.currentIndex.value, currentBefore);
      },
    );
  });

  group('repeat modes on auto-advance', () {
    test('repeat-one reloads the same track', () async {
      final a = await realTrack('a', 'A');
      final b = await realTrack('b', 'B');
      await repo.playQueue([a, b], startIndex: 0);
      repo.setRepeatMode(RepeatMode.one);

      engine.emitCompletion();
      await pumpUntil(() => engine.loadedTracks.length == 2);

      expect(engine.loadedTracks.last.$1.id, 'a');
      expect(
        engine.loadedTracks.last.$2,
        isTrue,
        reason: 'auto-advance must autoplay',
      );
    });

    test('repeat-all advances then wraps to the first track', () async {
      final a = await realTrack('a', 'A');
      final b = await realTrack('b', 'B');
      await repo.playQueue([a, b], startIndex: 0);
      repo.setRepeatMode(RepeatMode.all);

      engine.emitCompletion();
      await pumpUntil(() => engine.loadedTracks.length == 2);
      expect(engine.loadedTracks[1].$1.id, 'b');

      engine.emitCompletion();
      await pumpUntil(() => engine.loadedTracks.length == 3);
      expect(engine.loadedTracks[2].$1.id, 'a');
    });

    test('repeat-off stops at the end instead of advancing', () async {
      final only = await realTrack('only', 'Only');
      await repo.playQueue([only], startIndex: 0);
      repo.setRepeatMode(RepeatMode.off);
      expect(engine.loadedTracks, hasLength(1));

      engine.emitCompletion();
      await pumpUntil(() => !engine.playing);

      expect(
        engine.loadedTracks,
        hasLength(1),
        reason: 'no further track may load at the end of the queue',
      );
      expect(engine.seekToZeroCount, greaterThanOrEqualTo(1));
      expect(engine.playing, isFalse);
    });
  });

  group('play statistics', () {
    test(
      'registerPlay persists playCount/lastPlayedAt via the library store',
      () async {
        final track = await realTrack('stat', 'Stat Song');
        await store.save([track]);

        await repo.playQueue([track], startIndex: 0);

        final persisted = await store.load();
        final updated = persisted.singleWhere((t) => t.id == 'stat');
        expect(updated.playCount, 1);
        expect(updated.lastPlayedAt, isNotNull);

        // A second activation bumps again (repeat-one style replay).
        await repo.playQueue([updated], startIndex: 0);
        final persistedAgain = await store.load();
        expect(persistedAgain.singleWhere((t) => t.id == 'stat').playCount, 2);
      },
    );

    test('paused starts do not count as plays', () async {
      final track = await realTrack('quiet', 'Quiet Song');
      await store.save([track]);

      await repo.playQueue([track], startIndex: 0, autoplay: false);

      final persisted = await store.load();
      expect(persisted.singleWhere((t) => t.id == 'quiet').playCount, 0);
    });
  });

  group('transport', () {
    test('togglePlayPause flips the playing state', () async {
      final track = await realTrack('t', 'T');
      await repo.playQueue([track], startIndex: 0);
      expect(repo.playing.value, isTrue);

      await repo.togglePlayPause();
      expect(repo.playing.value, isFalse);

      await repo.togglePlayPause();
      expect(repo.playing.value, isTrue);
    });

    test('seekToFraction clamps and scales by duration', () async {
      final track = await realTrack('t', 'T'); // durationMs 60000
      await repo.playQueue([track], startIndex: 0);

      await repo.seekToFraction(0.5);
      expect(engine.position, const Duration(seconds: 30));

      await repo.seekToFraction(5.0); // clamped to 1.0
      expect(engine.position, const Duration(seconds: 60));
    });

    test('previous restarts the track after the threshold', () async {
      final a = await realTrack('a', 'A');
      final b = await realTrack('b', 'B');
      await repo.playQueue([a, b], startIndex: 1);

      engine.position = const Duration(seconds: 10);
      await repo.previous();

      expect(engine.seekToZeroCount, 1);
      expect(
        repo.currentIndex.value,
        1,
        reason: 'deep into a track, previous restarts it',
      );
    });
  });
}
