import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:on_audio_query/on_audio_query.dart';

import '../../../domain/models/track.dart';

/// Device media-library scanner.
///
/// - **Android**: wraps `on_audio_query` (`querySongs`) and maps results to
///   domain [Track]s with `TrackSource.device`.
/// - **iOS**: scanning is intentionally unsupported — device-library import
///   goes through `ImportExportRepository.importFromMusicApp` (the P2 native
///   `MPMediaPickerController` channel). All methods return empty/false.
/// - **Other platforms / web**: unsupported; everything degrades gracefully
///   so the UI can show its own messaging.
///
/// Permission handling reuses `on_audio_query`'s built-in permission API —
/// no additional dependency (permission_handler was deliberately not added).
class DeviceMediaService {
  DeviceMediaService({OnAudioQuery? audioQuery})
    : _audioQuery = audioQuery ?? OnAudioQuery();

  final OnAudioQuery _audioQuery;

  /// Whether a device scan may run right now.
  ///
  /// on_audio_query 2.9.x exposes permission checks as plain booleans
  /// (`permissionsStatus()` / `permissionsRequest()` → `Future<bool>`).
  Future<bool> hasPermission() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      return await _audioQuery.permissionsStatus();
    } catch (_) {
      // Missing plugin / unsupported platform → treat as no permission.
      return false;
    }
  }

  /// Requests scan permission (Android runtime dialog). Returns whether it
  /// ended up granted.
  Future<bool> requestPermission() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      return await _audioQuery.permissionsRequest();
    } catch (_) {
      return false;
    }
  }

  /// Scans the device media store. Empty list when unsupported or not
  /// permitted — callers surface their own messaging.
  Future<List<Track>> scanSongs() async {
    if (kIsWeb || !Platform.isAndroid) return const [];
    if (!await hasPermission()) return const [];

    try {
      final songs = await _audioQuery.querySongs(
        sortType: SongSortType.TITLE,
        orderType: OrderType.ASC_OR_SMALLER,
      );
      return [for (final song in songs) _toTrack(song)];
    } catch (_) {
      // A failed scan must never crash the app; UI shows an empty state.
      return const [];
    }
  }

  Track _toTrack(SongModel song) {
    final artist = song.artist?.trim() ?? '';
    return Track(
      id: 'device-${song.id}',
      title: song.title.trim().isEmpty ? 'Untitled' : song.title,
      artist: artist.isEmpty ? 'Unknown' : artist,
      album: song.album ?? '',
      durationMs: song.duration ?? 0,
      filePath: song.data,
      source: TrackSource.device,
      addedAt: DateTime.now(),
    );
  }
}

/*
 * Note on artwork: `queryArtwork` returns raw bytes rather than a file URI,
 * so device-library tracks carry no artworkPath/artworkUrl here. That matches
 * the documented limitation in docs/media-playback.md (lock-screen art needs
 * a file path or URL); exporting sidecar artwork is a future enhancement.
 */
