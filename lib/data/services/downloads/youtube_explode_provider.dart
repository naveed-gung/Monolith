import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

import 'source_provider.dart';

/// [SourceProvider] backed by `youtube_explode_dart` — a pure-Dart YouTube
/// client (no yt-dlp binary involved).
///
/// Ported from the v1 `_StreamMediaDownloader` (`lib/src/core/services/
/// media_downloader.dart`), keeping its battle-tested pieces:
/// - video-id resolution across URL variants (youtu.be, /shorts, /embed,
///   /live, watch?v=…, bare ids),
/// - preferred API clients ([yt.YoutubeApiClient.ios] first) to dodge
///   server-side bot challenges,
/// - best audio-only stream selection (mp4 → any direct container → fallback),
/// - chunked progress events and sidecar `<stem>.jpg` artwork,
/// - friendly 403/anti-bot error mapping.
///
/// Cancellation contract: the download is an `async*` stream; when the
/// consumer cancels the subscription the generator's `finally` block closes
/// the sink and deletes the partial file. YouTube streams are not resumable,
/// so pause/retry is implemented upstream as cancel + restart.
class YoutubeExplodeProvider implements SourceProvider {
  YoutubeExplodeProvider({
    required Future<Directory> Function() destinationDirectory,
    yt.YoutubeExplode? youtube,
    http.Client? httpClient,
  }) : _destinationDirectory = destinationDirectory,
       _youtube = youtube ?? yt.YoutubeExplode(),
       _httpClient = httpClient ?? http.Client();

  /// Where completed audio is written. Wired to [LibraryStore.musicDirectory]
  /// by the DI layer so downloads land in the library folder.
  final Future<Directory> Function() _destinationDirectory;
  final yt.YoutubeExplode _youtube;
  final http.Client _httpClient;

  /// Client order mirrors v1: iOS endpoints currently see the fewest
  /// anti-bot challenges; VR/Android act as fallbacks.
  /// (`YoutubeApiClient` instances are not const-constructible.)
  static final List<yt.YoutubeApiClient> _preferredClients =
      <yt.YoutubeApiClient>[
        yt.YoutubeApiClient.ios,
        yt.YoutubeApiClient.androidVr,
        yt.YoutubeApiClient.android,
      ];

  @override
  String get id => 'youtube';

  @override
  Future<DownloadPreview> inspect(Uri source) async {
    final video = await _youtube.videos.get(_resolveTarget(source));
    return DownloadPreview(
      title: video.title.trim().isEmpty ? 'Untitled' : video.title,
      artist: video.author.trim().isEmpty ? null : video.author,
      durationMs: video.duration?.inMilliseconds,
      artworkUrl: video.thumbnails.highResUrl,
      suggestedFileName: video.title,
    );
  }

  @override
  Stream<DownloadEvent> download(DownloadRequest req) async* {
    File? outputFile;
    IOSink? sink;
    var finished = false;

    try {
      final video = await _youtube.videos.get(_resolveTarget(req.sourceUri));
      final manifest = await _youtube.videos.streams.getManifest(
        video.id,
        ytClients: _preferredClients,
      );
      final stream = _selectAudioStream(manifest.audioOnly);
      if (stream == null) {
        throw StateError(
          'No downloadable audio stream was found for this video.',
        );
      }

      final directory = await _destinationDirectory();
      await directory.create(recursive: true);

      // The real extension depends on the selected container, so the request
      // name is treated as a stem.
      final stem = _stemOf(req.fileName);
      outputFile = File(
        '${directory.path}${Platform.pathSeparator}'
        '$stem.${_extensionFor(stream.container)}',
      );
      if (await outputFile.exists()) {
        await outputFile.delete();
      }
      sink = outputFile.openWrite();

      final totalBytes = stream.size.totalBytes;
      var received = 0;
      yield DownloadProgress(received: 0, total: totalBytes);

      await for (final chunk in _youtube.videos.streams.get(stream)) {
        sink.add(chunk);
        received += chunk.length;
        yield DownloadProgress(received: received, total: totalBytes);
      }

      await sink.flush();
      await sink.close();
      sink = null;

      // Sidecar artwork next to the audio file — LibraryStore picks it up as
      // artworkPath on registration (best-effort, never fails the download).
      await _tryWriteArtwork(
        video,
        '${directory.path}${Platform.pathSeparator}$stem.jpg',
      );

      finished = true;
      yield DownloadCompleted(filePath: outputFile.path);
    } catch (error) {
      yield DownloadFailed(message: normalizeDownloadError(error));
    } finally {
      try {
        await sink?.flush();
        await sink?.close();
      } catch (_) {
        // Sink already closed or broken; cleanup below still runs.
      }
      if (!finished && outputFile != null && await outputFile.exists()) {
        try {
          await outputFile.delete();
        } catch (_) {
          // Best-effort; a leftover partial must not mask the real error.
        }
      }
    }
  }

  /// Releases the underlying HTTP/YT clients. Call once at app shutdown.
  void dispose() {
    _httpClient.close();
    _youtube.close();
  }

  // ------------------------------------------------------------------
  // Ported helpers (v1 parity)
  // ------------------------------------------------------------------

  /// Prefers mp4 audio-only at the highest bitrate, then any non-HLS direct
  /// stream, then anything at all. Mirrors `_selectAudioStream` in v1.
  yt.AudioOnlyStreamInfo? _selectAudioStream(
    Iterable<yt.AudioOnlyStreamInfo> streams,
  ) {
    final list = streams.toList(growable: false);
    if (list.isEmpty) return null;

    final mp4Streams = list
        .where((stream) => stream.container == yt.StreamContainer.mp4)
        .toList(growable: false);
    if (mp4Streams.isNotEmpty) return mp4Streams.withHighestBitrate();

    final directStreams = list
        .where((stream) => stream.container != yt.StreamContainer.m3u8)
        .toList(growable: false);
    if (directStreams.isNotEmpty) return directStreams.withHighestBitrate();

    return list.withHighestBitrate();
  }

  /// Resolves URL variants down to what `videos.get` accepts. Handles
  /// `youtu.be/<id>`, `/shorts|/embed|/live|/v/<id>`, `watch?v=<id>`, bare
  /// ids and falls back to passing the raw string through (the library
  /// parses those too).
  Object _resolveTarget(Uri source) {
    final id = source.isScheme('http') || source.isScheme('https')
        ? _extractVideoId(source)
        : null;
    return id ?? source.toString();
  }

  String? _extractVideoId(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host == 'youtu.be') {
      return uri.pathSegments.isEmpty ? null : uri.pathSegments.first;
    }
    if (host.endsWith('youtube.com') || host.endsWith('youtube-nocookie.com')) {
      final segments = uri.pathSegments;
      if (segments.length >= 2) {
        const prefixes = {'shorts', 'embed', 'live', 'v'};
        if (prefixes.contains(segments.first.toLowerCase())) {
          return segments[1];
        }
      }
      return uri.queryParameters['v'];
    }
    return null;
  }

  Future<void> _tryWriteArtwork(yt.Video video, String destinationPath) async {
    try {
      final response = await _httpClient.get(
        Uri.parse(video.thumbnails.highResUrl),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) return;
      await File(destinationPath).writeAsBytes(response.bodyBytes, flush: true);
    } catch (_) {
      // Artwork is decorative; never fail the download over it.
    }
  }

  /// Maps raw errors to user-facing messages, with special handling for the
  /// 403 / anti-bot-challenge family (ported from v1 `_normalizeDownloadError`).
  static String normalizeDownloadError(Object error) {
    final message = error.toString().trim();
    final lower = message.toLowerCase();
    if (lower.contains('403') ||
        lower.contains('forbidden') ||
        lower.contains('sign in to confirm you') ||
        lower.contains('challenge request')) {
      return 'The source blocked this download request (403 / anti-bot '
          'challenge), so Monolith stopped it before saving anything.';
    }
    return 'Download failed: $message';
  }

  static String _extensionFor(yt.StreamContainer container) =>
      container == yt.StreamContainer.mp4 ? 'm4a' : container.name;

  static String _stemOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    return dot <= 0 ? fileName : fileName.substring(0, dot);
  }
}
