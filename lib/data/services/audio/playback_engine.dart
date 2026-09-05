import '../../../domain/models/track.dart';

/// Storage-agnostic playback facade consumed by `PlaybackRepository`.
///
/// The concrete just_audio implementation lives in `PlaybackService`; tests
/// substitute a fake engine so queue/repeat/shuffle logic runs without any
/// audio backend (see `test/playback_repository_test.dart`).
abstract interface class PlaybackEngine {
  /// Whether audio is currently playing.
  bool get playing;

  /// Current playback position.
  Duration get position;

  /// Duration of the loaded track; null while unknown.
  Duration? get duration;

  /// Emitted whenever the play/pause state flips.
  Stream<bool> get playingStream;

  /// Position updates, throttled to roughly 1 Hz — enough for progress bars
  /// without driving continuous repaints (rebuild plan §3.4).
  Stream<Duration> get positionStream;

  /// Duration of the loaded track (null while unknown).
  Stream<Duration?> get durationStream;

  /// Fires once when the loaded track plays through to the end.
  ///
  /// Also fires when the user seeks to the very end — the repository treats
  /// both as "track finished".
  Stream<void> get completionStream;

  /// Replaces the single audio source with [track]'s local file.
  ///
  /// Single-source by design: the queue is managed by the repository, which
  /// is more reliable than engine-side concatenation for this app.
  Future<void> loadTrack(Track track, {bool autoplay = true});

  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> setSpeed(double speed);

  /// Applies the mild headroom reduction (target 0.84 ≈ −1.5 dB) or restores
  /// unity gain. See docs/media-playback.md — this is clipping prevention,
  /// not LUFS loudness normalisation.
  Future<void> applyNormalization(bool enabled);

  /// Ramps the volume to [volume] over [ms] milliseconds to eliminate the
  /// audible click of cutting a waveform mid-sample.
  Future<void> fadeTo(double volume, {int ms = 220});

  /// Releases the underlying player resources.
  void dispose();
}
