import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../domain/models/enums.dart';
import '../../domain/models/track.dart';
import '../services/audio/playback_engine.dart';
import '../services/storage/library_store.dart';

/// Stateful playback orchestrator — the ViewModel role for the player feature.
///
/// Owns the app-managed queue, repeat/shuffle semantics and smart-playlist
/// bookkeeping. State is exposed as fine-grained [ValueNotifier]s so widgets
/// rebuild only for the slice they read (rebuild plan §3.4: no god-controller).
///
/// The engine is single-source by design: the repository advances the queue
/// itself, which is more reliable than engine-side concatenation.
class PlaybackRepository {
  PlaybackRepository({
    required PlaybackEngine engine,
    required LibraryStore libraryStore,
  }) : _engine = engine,
       _libraryStore = libraryStore {
    _subscriptions = [
      _engine.playingStream.listen(_onPlayingChanged),
      _engine.positionStream.listen(_onPositionChanged),
      _engine.durationStream.listen(_onDurationChanged),
      _engine.completionStream.listen((_) {
        unawaited(_onCompleted());
      }),
    ];
  }

  final PlaybackEngine _engine;
  final LibraryStore _libraryStore;

  late final List<StreamSubscription<void>> _subscriptions;

  // ---- Observable state (fine-grained) -----------------------------------

  /// Current playback queue (playable tracks only).
  final ValueNotifier<List<Track>> queue = ValueNotifier(const []);
  final ValueNotifier<int> currentIndex = ValueNotifier(0);
  final ValueNotifier<Track?> currentTrack = ValueNotifier(null);
  final ValueNotifier<bool> playing = ValueNotifier(false);
  final ValueNotifier<double> progress = ValueNotifier(0);
  final ValueNotifier<Duration> position = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration?> duration = ValueNotifier(null);
  final ValueNotifier<RepeatMode> repeatMode = ValueNotifier(RepeatMode.off);
  final ValueNotifier<ShuffleMode> shuffleMode = ValueNotifier(ShuffleMode.off);

  /// Traversal order over [queue] indices — identity when shuffle is off,
  /// a stable permutation when on. Exposed for "up next" surfaces and tests;
  /// only rebuilt when the queue changes or shuffle is toggled.
  List<int> get playOrder => List.unmodifiable(_order);

  // ---- Internal state -----------------------------------------------------

  List<Track> _queue = const [];
  List<int> _order = const [];
  int _orderPosition = 0;
  bool _registeredThisActivation = false;
  bool _disposed = false;
  Future<void> _registration = Future<void>.value();
  List<Track>? _libraryCache;

  /// Restart-vs-previous-track threshold, matching common player behaviour.
  static const Duration _previousRestartThreshold = Duration(seconds: 3);

  // ---- Queue control ------------------------------------------------------

  /// Loads [tracks] as the new queue and activates [startIndex].
  ///
  /// Entries without a playable file are filtered out up front; if nothing
  /// playable remains the call is a no-op.
  Future<void> playQueue(
    List<Track> tracks, {
    int startIndex = 0,
    bool autoplay = true,
  }) async {
    final playable = tracks.where((t) => t.filePath.trim().isNotEmpty).toList();
    if (playable.isEmpty) return;

    _queue = List.unmodifiable(playable);
    queue.value = _queue;
    final start = startIndex.clamp(0, _queue.length - 1);
    _rebuildOrder(keepOriginalIndex: start);
    await _activate(_order.indexOf(start), autoplay: autoplay);
  }

  Future<void> togglePlayPause() async {
    if (currentTrack.value == null) {
      if (_queue.isNotEmpty) {
        await _activate(_orderPosition, autoplay: true);
      }
      return;
    }
    if (_engine.playing) {
      await _engine.pause();
    } else {
      await _engine.play();
    }
  }

  /// Manual skip forward. Always wraps to the start of the order.
  Future<void> next() async {
    if (_queue.isEmpty) return;
    await _activate((_orderPosition + 1) % _order.length, autoplay: true);
  }

  /// Restart the current track when it has been playing for a while,
  /// otherwise step back in traversal order (wrapping under repeat-all).
  Future<void> previous() async {
    if (_queue.isEmpty) return;
    if (_engine.position > _previousRestartThreshold) {
      await _engine.seek(Duration.zero);
      return;
    }
    final target = _orderPosition == 0
        ? (repeatMode.value == RepeatMode.all ? _order.length - 1 : 0)
        : _orderPosition - 1;
    await _activate(target, autoplay: true);
  }

  Future<void> seekTo(Duration target) => _engine.seek(target);

  Future<void> seekToFraction(double fraction) {
    final total = duration.value ?? Duration.zero;
    final clamped = fraction.clamp(0.0, 1.0);
    return _engine.seek(
      Duration(milliseconds: (total.inMilliseconds * clamped).round()),
    );
  }

  void setRepeatMode(RepeatMode mode) => repeatMode.value = mode;

  /// Toggles shuffle. The stored permutation is rebuilt with the current
  /// track pinned first so playback continues seamlessly.
  void setShuffleEnabled(bool enabled) {
    shuffleMode.value = enabled ? ShuffleMode.all : ShuffleMode.off;
    if (_queue.isEmpty) return;
    final keep = currentIndex.value.clamp(0, _queue.length - 1);
    _rebuildOrder(keepOriginalIndex: keep);
    _orderPosition = _order.indexOf(keep);
  }

  /// Bumps play statistics for [track] and persists them through
  /// [LibraryStore.save]. Returns the updated copy.
  Future<Track> registerPlay(Track track) async {
    final updated = track.copyWith(
      playCount: track.playCount + 1,
      lastPlayedAt: DateTime.now(),
    );

    final library = _libraryCache ??= await _libraryStore.load();
    final index = library.indexWhere((t) => t.id == updated.id);
    final merged = [...library];
    if (index >= 0) {
      merged[index] = updated;
    } else {
      merged.add(updated);
    }
    _libraryCache = merged;
    await _libraryStore.save(merged);
    return updated;
  }

  /// Completes pending statistics writes before an owner removes the store.
  Future<void> close() async {
    dispose();
    await _registration;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    queue.dispose();
    currentIndex.dispose();
    currentTrack.dispose();
    playing.dispose();
    progress.dispose();
    position.dispose();
    duration.dispose();
    repeatMode.dispose();
    shuffleMode.dispose();
  }

  // ---- Internals -----------------------------------------------------------

  Future<void> _activate(int orderPosition, {required bool autoplay}) async {
    if (_disposed || _queue.isEmpty || _order.isEmpty) return;
    final clamped = orderPosition.clamp(0, _order.length - 1);
    _orderPosition = clamped;

    final originalIndex = _order[clamped];
    final track = _queue[originalIndex];

    currentIndex.value = originalIndex;
    currentTrack.value = track;
    position.value = Duration.zero;
    progress.value = 0;
    duration.value = track.durationMs > 0
        ? Duration(milliseconds: track.durationMs)
        : null;
    _registeredThisActivation = false;

    await _engine.loadTrack(track, autoplay: autoplay);
    if (_disposed) return;
    if (autoplay) {
      await _registerPlayIfNeeded();
    }
  }

  Future<void> _registerPlayIfNeeded() async {
    if (_disposed) return;
    final track = currentTrack.value;
    if (track == null) return;
    if (_registeredThisActivation) return _registration;
    if (!_engine.playing) return;
    _registeredThisActivation = true;
    _registration = _registration.then((_) async {
      await registerPlay(track);
    });
    await _registration;
  }

  /// Builds the traversal order. Shuffle keeps [keepOriginalIndex] first and
  /// randomises the rest — a stable stored permutation, not a per-advance
  /// reshuffle.
  void _rebuildOrder({int? keepOriginalIndex}) {
    final count = _queue.length;
    if (shuffleMode.value == ShuffleMode.off) {
      _order = List<int>.generate(count, (i) => i);
      return;
    }
    final rest = List<int>.generate(count, (i) => i);
    if (keepOriginalIndex != null) rest.remove(keepOriginalIndex);
    rest.shuffle(Random());
    _order = [?keepOriginalIndex, ...rest];
  }

  void _onPlayingChanged(bool value) {
    if (_disposed) return;
    playing.value = value;
    if (value) {
      unawaited(_registerPlayIfNeeded());
    }
  }

  void _onPositionChanged(Duration value) {
    position.value = value;
    final total = duration.value;
    progress.value = total == null || total.inMilliseconds <= 0
        ? 0.0
        : (value.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
  }

  void _onDurationChanged(Duration? value) => duration.value = value;

  /// Auto-advance on completion, honouring the repeat mode.
  Future<void> _onCompleted() async {
    if (_disposed || _queue.isEmpty || _order.isEmpty) return;
    switch (repeatMode.value) {
      case RepeatMode.one:
        await _activate(_orderPosition, autoplay: true);
      case RepeatMode.all:
        await _activate((_orderPosition + 1) % _order.length, autoplay: true);
      case RepeatMode.off:
        if (_orderPosition >= _order.length - 1) {
          // End of queue: rewind and stop instead of advancing.
          await _engine.seek(Duration.zero);
          await _engine.pause();
        } else {
          await _activate(_orderPosition + 1, autoplay: true);
        }
    }
  }
}
