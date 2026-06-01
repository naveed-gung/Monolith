import 'package:flutter/foundation.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../models/music_models.dart';

class LocalMediaSnapshot {
  const LocalMediaSnapshot({
    required this.permissionGranted,
    required this.tracks,
    this.error,
  });

  final bool permissionGranted;
  final List<Track> tracks;
  final String? error;
}

class LocalMediaService {
  final OnAudioQuery _audioQuery = OnAudioQuery();

  Future<LocalMediaSnapshot> loadTracks({
    bool retryRequest = false,
    bool requestPermission = true,
  }) async {
    try {
      if (!requestPermission) {
        return const LocalMediaSnapshot(permissionGranted: false, tracks: []);
      }

      final permissionGranted = await _audioQuery.checkAndRequest(
        retryRequest: retryRequest,
      );

      if (!permissionGranted) {
        return const LocalMediaSnapshot(permissionGranted: false, tracks: []);
      }

      final songs = defaultTargetPlatform == TargetPlatform.android
          ? await _audioQuery.querySongs(
              sortType: SongSortType.DATE_ADDED,
              orderType: OrderType.DESC_OR_GREATER,
              uriType: UriType.EXTERNAL,
            )
          : await _audioQuery.querySongs(
              sortType: SongSortType.DATE_ADDED,
              orderType: OrderType.DESC_OR_GREATER,
            );

      final tracks = songs
          .where((song) => song.duration != null && song.duration! > 0)
          .map(_mapSong)
          .toList();

      return LocalMediaSnapshot(permissionGranted: true, tracks: tracks);
    } catch (error) {
      return LocalMediaSnapshot(
        permissionGranted: false,
        tracks: const [],
        error: 'Unable to read the device library: $error',
      );
    }
  }

  Future<void> scanMedia(String path) async {
    try {
      await _audioQuery.scanMedia(path);
    } catch (_) {
      // Ignore scan failures. The app keeps its own manifest for downloads.
    }
  }

  Track _mapSong(SongModel song) {
    final artist = _cleanLabel(song.artist, 'Unknown artist');
    final album = _cleanLabel(song.album, 'Unknown album');
    final genre = _cleanLabel(song.genre, 'Device audio');
    final paletteSeed = '${song.title}-$artist-$album';

    return Track(
      id: 'device-${song.id}',
      title: song.title,
      artist: artist,
      album: album,
      genre: genre,
      duration: Duration(milliseconds: song.duration ?? 0),
      colors: Track.paletteForSeed(paletteSeed),
      blurb: '$artist in $album',
      source: TrackSource.device,
      filePath: song.data,
      artworkQueryId: song.id,
    );
  }

  String _cleanLabel(String? value, String fallback) {
    if (value == null || value.trim().isEmpty || value == '<unknown>') {
      return fallback;
    }
    return value.trim();
  }
}
