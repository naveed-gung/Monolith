import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../../../domain/models/track.dart';
import 'playback_engine.dart';

/// just_audio-backed [PlaybackEngine].
///
/// Init-order contract (docs/media-playback.md — critical, do not reorder):
/// 1. `JustAudioBackground.init(...)` runs in `main()` **before** `runApp()`
///    (wired in the upcoming UI/bootstrap phase).
/// 2. [configureSession] completes **before** the first [loadTrack].
class PlaybackService implements PlaybackEngine {
  PlaybackService({AudioPlayer? player}) : _player = player ?? AudioPlayer() {
    _stateSub = _player.playerStateStream.listen(_onPlayerState);
  }

  final AudioPlayer _player;
  late final StreamSubscription<PlayerState> _stateSub;

  final StreamController<void> _completions = StreamController.broadcast();
  bool _completionArmed = false;

  /// Target volume when normalisation is enabled (≈ −1.5 dB headroom).
  static const double normalizedVolume = 0.84;

  static const int _fadeSteps = 12;

  /// Position sample cadence for UI progress bars (~0.75 Hz, within the
  /// 500 ms–1 s budget from the rebuild plan).
  static const Duration _positionInterval = Duration(milliseconds: 750);

  bool _normalizationEnabled = false;
  bool _smoothTransitions = true;
  int _fadeToken = 0;
  Stream<Duration>? _throttledPositions;

  /// Configures the OS audio session as a music player. Must complete before
  /// any audio source is loaded (docs/media-playback.md §Initialisation
  /// Order, step 5).
  static Future<void> configureSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  }

  /// Enables/disables the short volume ramp around track switches.
  set smoothTransitions(bool enabled) => _smoothTransitions = enabled;

  @override
  bool get playing => _player.playing;

  @override
  Duration get position => _player.position;

  @override
  Duration? get duration => _player.duration;

  @override
  Stream<bool> get playingStream => _player.playingStream;

  @override
  Stream<Duration> get positionStream => _throttledPositions ??= _player
      .positionStream
      .transform(_Throttle<Duration>(_positionInterval));

  @override
  Stream<Duration?> get durationStream => _player.durationStream;

  @override
  Stream<void> get completionStream => _completions.stream;

  @override
  Future<void> loadTrack(Track track, {bool autoplay = true}) async {
    if (track.filePath.trim().isEmpty) {
      throw ArgumentError.value(track, 'track', 'has no playable file');
    }
    _completionArmed = false;

    // Smooth hand-over: ramp down, stop, swap source, ramp back up.
    if (_smoothTransitions && _player.playing) {
      await fadeTo(0);
      await _player.pause();
    }

    await _player.setAudioSource(
      AudioSource.uri(Uri.file(track.filePath), tag: _mediaItemFor(track)),
    );

    if (autoplay) {
      await _player.play();
      if (_smoothTransitions) {
        await fadeTo(_targetVolume);
      }
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) =>
      _player.setVolume(volume.clamp(0.0, 1.0));

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> applyNormalization(bool enabled) async {
    _normalizationEnabled = enabled;
    await _player.setVolume(_targetVolume);
  }

  /// Twelve-step volume ramp (ported from the v1 `_fadeVolume`) — barely
  /// perceptible, but eliminates hard waveform cuts. A newer call supersedes
  /// an in-flight fade via a token check.
  @override
  Future<void> fadeTo(double volume, {int ms = 220}) async {
    final token = ++_fadeToken;
    const steps = _fadeSteps;
    final from = _player.volume;
    final diff = (volume.clamp(0.0, 1.0) - from) / steps;
    for (var i = 1; i <= steps; i++) {
      await Future<void>.delayed(Duration(milliseconds: ms ~/ steps));
      if (token != _fadeToken) return;
      await _player.setVolume((from + diff * i).clamp(0.0, 1.0));
    }
  }

  @override
  void dispose() {
    _stateSub.cancel();
    _completions.close();
    _player.dispose();
  }

  double get _targetVolume => _normalizationEnabled ? normalizedVolume : 1.0;

  void _onPlayerState(PlayerState state) {
    if (state.processingState == ProcessingState.completed &&
        _completionArmed) {
      _completionArmed = false;
      _completions.add(null);
    } else if (state.processingState == ProcessingState.ready) {
      _completionArmed = true;
    }
  }

  /// Builds the OS-facing metadata payload. Artwork priority mirrors the v1
  /// controller: local sidecar file first, remote URL second, none last.
  MediaItem _mediaItemFor(Track track) {
    Uri? artUri;
    final artPath = track.artworkPath;
    if (artPath != null && artPath.trim().isNotEmpty) {
      artUri = Uri.file(artPath);
    } else {
      final url = track.artworkUrl;
      if (url != null && url.trim().isNotEmpty) {
        artUri = Uri.tryParse(url);
      }
    }
    return MediaItem(
      id: track.id,
      title: track.title.trim().isEmpty ? 'Untitled' : track.title,
      artist: track.artist,
      album: track.album.trim().isEmpty ? 'Monolith' : track.album,
      duration: track.durationMs > 0
          ? Duration(milliseconds: track.durationMs)
          : null,
      artUri: artUri,
    );
  }
}

/// Drops intermediate values so consumers receive at most one sample per
/// [interval] — a dependency-free stand-in for rxdart's `sampleTime`
/// (adding rxdart for one operator was judged not worth it).
class _Throttle<T> extends StreamTransformerBase<T, T> {
  const _Throttle(this.interval);

  final Duration interval;

  @override
  Stream<T> bind(Stream<T> stream) {
    late StreamController<T> controller;
    late StreamSubscription<T> subscription;
    var lastEmitAt = DateTime.fromMillisecondsSinceEpoch(0);

    controller = StreamController<T>(
      onListen: () {
        subscription = stream.listen(
          (data) {
            final now = DateTime.now();
            if (now.difference(lastEmitAt) >= interval) {
              lastEmitAt = now;
              controller.add(data);
            }
          },
          onError: controller.addError,
          onDone: controller.close,
        );
      },
      onPause: () => subscription.pause(),
      onResume: () => subscription.resume(),
      onCancel: () => subscription.cancel(),
    );
    return controller.stream;
  }
}
