import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

import 'media_downloader_models.dart';
import 'audio_stream_transfer.dart';
import 'native_audio_extractor.dart';

abstract class MediaDownloader {
  Stream<DownloadProgress> get onProgress;
  Stream<DownloadState> get onStateChanged;
  Stream<DownloadError> get onError;
  Stream<LogMessage> get onLog;

  Future<InitResult> initialize({
    bool enableFFmpeg = true,
    bool enableAria2c = false,
  });

  Future<UpdateResult> updateYoutubeDL({
    UpdateChannel channel = UpdateChannel.stable,
  });

  Future<VideoInfo> getVideoInfo(String url);

  Future<DownloadResult> download(DownloadRequest request);

  Future<bool> cancelDownload(String processId);

  void dispose();

  factory MediaDownloader.platform() {
    if (kIsWeb) {
      return const _UnsupportedMediaDownloader(
        'The downloader is unavailable on the web.',
      );
    }

    return _StreamMediaDownloader();
  }
}

class _StreamMediaDownloader implements MediaDownloader {
  _StreamMediaDownloader();

  final Map<String, yt.Video> _previews = {};

  final yt.YoutubeExplode _youtube = yt.YoutubeExplode();
  final http.Client _httpClient = http.Client();
  final StreamController<DownloadProgress> _progressController =
      StreamController<DownloadProgress>.broadcast();
  final StreamController<DownloadState> _stateController =
      StreamController<DownloadState>.broadcast();
  final StreamController<DownloadError> _errorController =
      StreamController<DownloadError>.broadcast();
  final StreamController<LogMessage> _logController =
      StreamController<LogMessage>.broadcast();
  final Map<String, _ActiveDownload> _activeDownloads =
      <String, _ActiveDownload>{};

  bool _isInitialized = false;

  @override
  Stream<DownloadProgress> get onProgress => _progressController.stream;

  @override
  Stream<DownloadState> get onStateChanged => _stateController.stream;

  @override
  Stream<DownloadError> get onError => _errorController.stream;

  @override
  Stream<LogMessage> get onLog => _logController.stream;

  @override
  Future<InitResult> initialize({
    bool enableFFmpeg = true,
    bool enableAria2c = false,
  }) async {
    _isInitialized = true;
    return InitResult(success: true);
  }

  @override
  Future<UpdateResult> updateYoutubeDL({
    UpdateChannel channel = UpdateChannel.stable,
  }) async {
    return UpdateResult(
      status: OperationStatus.error,
      version: 'stream-fallback',
      errorMessage: 'The built-in downloader does not use yt-dlp binaries.',
    );
  }

  @override
  Future<VideoInfo> getVideoInfo(String url) async {
    await _ensureInitialized();

    final video = await _youtube.videos
        .get(url)
        .timeout(const Duration(seconds: 25));
    if (_previews.length >= 8) _previews.remove(_previews.keys.first);
    _previews[url] = video;

    return VideoInfo(
      id: video.id.value,
      title: video.title,
      description: video.description,
      uploader: video.author,
      uploaderId: video.channelId.toString(),
      uploaderUrl: _channelUrl(video),
      channelId: video.channelId.toString(),
      channelUrl: _channelUrl(video),
      duration: video.duration?.inSeconds,
      viewCount: video.engagement.viewCount,
      likeCount: video.engagement.likeCount,
      thumbnail: _thumbnailUrl(video),
      url: video.url,
    );
  }

  @override
  Future<DownloadResult> download(DownloadRequest request) async {
    final processId = _normalizeProcessId(request.processId);
    if (_activeDownloads.containsKey(processId)) {
      return DownloadResult(
        status: OperationStatus.error,
        errorMessage: 'A download with this identifier is already running.',
      );
    }

    final activeDownload = _ActiveDownload(processId: processId);
    _activeDownloads[processId] = activeDownload;

    try {
      await _ensureInitialized();
      _emitState(processId, DownloadStateType.started);
      _log(processId, 'Inspecting available YouTube audio streams.');

      final video =
          _previews[request.url] ??
          await activeDownload.waitFor<yt.Video>(
            activeDownload.youtube.videos.get(request.url),
          );
      // Try at most two independently resolved mobile manifests. Never let an
      // extractor retry HTTP failures forever behind a zero-percent task.
      Object? transferError;
      File? completedFile;
      for (final client in [
        yt.YoutubeApiClient.androidSdkless,
        yt.YoutubeApiClient.ios,
      ]) {
        activeDownload.checkCancelled();
        try {
          final manifest = await activeDownload.waitFor(
            activeDownload.youtube.videos.streams.getManifest(
              video.id,
              ytClients: [client],
            ),
          );
          final audio = _selectAudioStream(
            manifest.audioOnly.where((s) => s.fragments.isEmpty),
          );
          final combined =
              manifest.muxed
                  .where(
                    (s) =>
                        s.container == yt.StreamContainer.mp4 &&
                        s.fragments.isEmpty,
                  )
                  .toList()
                ..sort(
                  (a, b) => a.size.totalBytes.compareTo(b.size.totalBytes),
                );
          final candidates = <yt.StreamInfo>[
            ?audio,
            if ((Platform.isIOS || Platform.isAndroid) && combined.isNotEmpty)
              combined.first,
          ];
          if (candidates.isEmpty) {
            throw StateError('No compatible audio source was found.');
          }
          for (final selectedStream in candidates) {
            try {
              final needsExtraction = selectedStream is yt.MuxedStreamInfo;
              final finalFile = await _prepareOutputFile(
                request: request,
                video: video,
                stream: selectedStream,
              );
              File outputFile;
              if (needsExtraction) {
                activeDownload.staging = await Directory.systemTemp.createTemp(
                  'monolith_audio_',
                );
                outputFile = File('${activeDownload.staging!.path}/source.mp4');
                _log(
                  processId,
                  'Trying a compatible source; keeping only its audio.',
                );
              } else {
                outputFile = File('${finalFile.path}.part');
              }
              activeDownload.outputFile = outputFile;
              activeDownload.checkCancelled();
              activeDownload.transfer = AudioStreamTransfer();
              final watch = Stopwatch()..start();
              var lastProgress = -250;
              _emitProgress(
                processId: processId,
                downloadedBytes: 0,
                totalBytes: selectedStream.size.totalBytes,
                elapsed: Duration.zero,
              );
              _log(processId, 'Connecting to audio source…');
              await activeDownload.transfer!.download(
                url: selectedStream.url,
                headers: {
                  if (client.payload['context']['client']['userAgent']
                      case final String agent)
                    'User-Agent': agent,
                },
                size: selectedStream.size.totalBytes,
                destination: outputFile,
                onProgress: (received) {
                  if (activeDownload.cancelled ||
                      watch.elapsedMilliseconds - lastProgress < 250) {
                    return;
                  }
                  lastProgress = watch.elapsedMilliseconds;
                  _emitProgress(
                    processId: processId,
                    downloadedBytes: received,
                    totalBytes: selectedStream.size.totalBytes,
                    elapsed: watch.elapsed,
                  );
                },
              );
              activeDownload.checkCancelled();
              if (await outputFile.length() != selectedStream.size.totalBytes) {
                throw StateError('Audio download is incomplete.');
              }
              _emitProgress(
                processId: processId,
                downloadedBytes: selectedStream.size.totalBytes,
                totalBytes: selectedStream.size.totalBytes,
                elapsed: watch.elapsed,
              );
              if (needsExtraction) {
                _log(processId, 'Saving audio…');
                final audioFile = File(
                  '${activeDownload.staging!.path}/audio.m4a',
                );
                activeDownload.checkCancelled();
                await activeDownload.extractor.extract(
                  processId,
                  outputFile.path,
                  audioFile.path,
                );
                activeDownload.checkCancelled();
                if (!await audioFile.exists() ||
                    await audioFile.length() == 0) {
                  throw StateError('Audio extraction produced no audio.');
                }
                final stagedAudio = File('${finalFile.path}.part');
                activeDownload.outputFile = stagedAudio;
                await audioFile.copy(stagedAudio.path);
              }
              completedFile = finalFile;
              break;
            } catch (error) {
              transferError = error;
              await _deletePartialFiles(activeDownload);
              activeDownload.checkCancelled();
            }
          }
          if (completedFile != null) break;
        } catch (error) {
          transferError = error;
          await _deletePartialFiles(activeDownload);
          activeDownload.checkCancelled();
          _log(
            processId,
            'Audio source failed; trying the remaining compatible source.',
            LogLevel.warning,
          );
        }
      }
      if (completedFile == null) {
        throw transferError ?? StateError('No audio source available.');
      }
      if (request.embedThumbnail == true) {
        activeDownload.artworkFile = File(
          '${_fileStem(completedFile.path)}.jpg',
        );
        await _downloadThumbnail(
          video: video,
          destination: activeDownload.artworkFile,
          processId: processId,
        );
      }
      activeDownload.checkCancelled();
      await activeDownload.outputFile!.rename(completedFile.path);
      activeDownload.outputFile = completedFile;
      _emitState(processId, DownloadStateType.completed);
      return DownloadResult(
        status: OperationStatus.success,
        outputPath: completedFile.path,
      );
    } catch (error) {
      await _deletePartialFiles(activeDownload);
      if (activeDownload.cancelled) {
        return DownloadResult(status: OperationStatus.cancelled);
      }
      final message = _normalizeDownloadError(error);
      _emitError(processId, message);
      return DownloadResult(
        status: OperationStatus.error,
        errorMessage: message,
      );
    } finally {
      if (identical(_activeDownloads[processId], activeDownload)) {
        _activeDownloads.remove(processId);
      }
      activeDownload.youtube.close();
      activeDownload.transfer?.cancel();
      await activeDownload.clearStaging();
    }
  }

  @override
  Future<bool> cancelDownload(String processId) async {
    final activeDownload = _activeDownloads[processId];
    if (activeDownload == null) {
      return false;
    }

    activeDownload.cancel();
    _emitState(processId, DownloadStateType.cancelled);
    // The owning download future removes its partial file after its writer exits.
    return true;
  }

  @override
  void dispose() {
    for (final activeDownload in _activeDownloads.values) {
      activeDownload.cancel();
    }
    _activeDownloads.clear();
    _httpClient.close();
    _youtube.close();
    _progressController.close();
    _stateController.close();
    _errorController.close();
    _logController.close();
  }

  Future<void> _ensureInitialized() async {
    if (_isInitialized) {
      return;
    }

    final result = await initialize();
    if (!result.success) {
      throw StateError(
        result.errorMessage ?? 'Unable to initialize the downloader.',
      );
    }
  }

  String _normalizeDownloadError(Object error) {
    final message = error.toString().trim();
    final lower = message.toLowerCase();
    if (lower.contains('403') ||
        lower.contains('forbidden') ||
        lower.contains('sign in to confirm you') ||
        lower.contains('challenge request')) {
      return 'YouTube refused this download (HTTP 403). Try again later or import the audio from Files.';
    }

    return 'Download failed: $message';
  }

  yt.AudioOnlyStreamInfo? _selectAudioStream(
    Iterable<yt.AudioOnlyStreamInfo> streams,
  ) {
    final streamList = streams.toList(growable: false);
    if (streamList.isEmpty) {
      return null;
    }

    final mp4Streams = streamList
        .where((stream) => stream.container == yt.StreamContainer.mp4)
        .toList(growable: false);
    if (mp4Streams.isNotEmpty) {
      // Standard AAC is the portable music choice. The highest bitrate entry
      // can instead be a surround variant with different source availability.
      return mp4Streams.where((stream) => stream.tag == 140).firstOrNull ??
          mp4Streams.withHighestBitrate();
    }

    if (Platform.isIOS) return null; // AVPlayer needs an AAC/MP4 stream.

    final directStreams = streamList
        .where((stream) => stream.container != yt.StreamContainer.m3u8)
        .toList(growable: false);
    if (directStreams.isNotEmpty) {
      return directStreams.withHighestBitrate();
    }

    return streamList.withHighestBitrate();
  }

  Future<File> _prepareOutputFile({
    required DownloadRequest request,
    required yt.Video video,
    required yt.StreamInfo stream,
  }) async {
    final outputDirectory = Directory(request.outputPath);
    if (!await outputDirectory.exists()) {
      await outputDirectory.create(recursive: true);
    }

    final baseName = _requestedBaseName(request.outputTemplate, video.title);
    final extension = _audioExtension(stream.container);
    final outputFile = File(
      '${outputDirectory.path}${Platform.pathSeparator}$baseName-${request.processId}.$extension',
    );
    if (await outputFile.exists()) {
      return File(
        '${outputDirectory.path}${Platform.pathSeparator}$baseName-${request.processId}.$extension',
      );
    }
    return outputFile;
  }

  Future<void> _downloadThumbnail({
    required yt.Video video,
    required File? destination,
    required String processId,
  }) async {
    if (destination == null) {
      return;
    }

    try {
      final response = await _httpClient
          .get(Uri.parse(_thumbnailUrl(video)))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _log(
          processId,
          'Skipping artwork download because the thumbnail request returned ${response.statusCode}.',
          LogLevel.warning,
        );
        return;
      }

      await destination.writeAsBytes(response.bodyBytes, flush: true);
    } catch (error) {
      _log(
        processId,
        'Skipping artwork download because it failed: $error',
        LogLevel.warning,
      );
    }
  }

  void _emitProgress({
    required String processId,
    required int downloadedBytes,
    required int totalBytes,
    required Duration elapsed,
  }) {
    if (_progressController.isClosed) {
      return;
    }

    final normalizedTotal = totalBytes <= 0 ? 1 : totalBytes;
    final progress = (downloadedBytes / normalizedTotal * 100)
        .clamp(0, 100)
        .toDouble();
    final eta = _estimateEtaSeconds(
      downloadedBytes: downloadedBytes,
      totalBytes: normalizedTotal,
      elapsed: elapsed,
    );
    final elapsedSeconds = elapsed.inMilliseconds / 1000.0;
    final speed = elapsedSeconds > 0
        ? (downloadedBytes / elapsedSeconds).round()
        : 0;

    _progressController.add(
      DownloadProgress(
        processId: processId,
        progress: progress,
        etaInSeconds: eta,
        totalBytes: totalBytes > 0 ? totalBytes : null,
        downloadedBytes: downloadedBytes,
        speedBytesPerSecond: speed > 0 ? speed : null,
      ),
    );
  }

  int _estimateEtaSeconds({
    required int downloadedBytes,
    required int totalBytes,
    required Duration elapsed,
  }) {
    if (downloadedBytes <= 0 || totalBytes <= downloadedBytes) {
      return 0;
    }

    final elapsedSeconds = elapsed.inMilliseconds / 1000;
    if (elapsedSeconds <= 0) {
      return 0;
    }

    final bytesPerSecond = downloadedBytes / elapsedSeconds;
    if (bytesPerSecond <= 0) {
      return 0;
    }

    final remainingBytes = totalBytes - downloadedBytes;
    return (remainingBytes / bytesPerSecond).round();
  }

  void _emitState(String processId, DownloadStateType state) {
    if (_stateController.isClosed) {
      return;
    }

    _stateController.add(DownloadState(processId: processId, state: state));
  }

  void _emitError(String processId, String message) {
    if (_errorController.isClosed) {
      return;
    }

    _errorController.add(DownloadError(processId: processId, error: message));
  }

  void _log(
    String processId,
    String message, [
    LogLevel level = LogLevel.info,
  ]) {
    if (_logController.isClosed) {
      return;
    }

    _logController.add(
      LogMessage(
        processId: processId,
        message: message,
        level: level,
        timestamp: DateTime.now(),
      ),
    );
  }

  Future<void> _deletePartialFiles(_ActiveDownload activeDownload) async {
    await activeDownload.clearStaging();
    final outputFile = activeDownload.outputFile;
    if (outputFile != null && await outputFile.exists()) {
      await outputFile.delete();
    }

    final artworkFile = activeDownload.artworkFile;
    if (artworkFile != null && await artworkFile.exists()) {
      await artworkFile.delete();
    }
  }

  String _normalizeProcessId(String? processId) {
    final trimmed = processId?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }

    return 'download_${DateTime.now().millisecondsSinceEpoch}';
  }

  String _requestedBaseName(String? outputTemplate, String fallbackTitle) {
    final template = outputTemplate?.trim();
    final fromTemplate = template == null || template.isEmpty
        ? fallbackTitle
        : template.replaceAll('.%(ext)s', '').replaceAll('%(ext)s', '');
    final sanitized = fromTemplate
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return sanitized.isEmpty ? 'Downloaded audio' : sanitized;
  }

  String _audioExtension(yt.StreamContainer container) {
    if (container == yt.StreamContainer.mp4) {
      return 'm4a';
    }

    return container.name;
  }

  String _thumbnailUrl(yt.Video video) => video.thumbnails.highResUrl;

  String _channelUrl(yt.Video video) =>
      'https://www.youtube.com/channel/${video.channelId}';

  String _fileStem(String path) {
    final dotIndex = path.lastIndexOf('.');
    if (dotIndex <= 0) {
      return path;
    }
    return path.substring(0, dotIndex);
  }
}

class _UnsupportedMediaDownloader implements MediaDownloader {
  const _UnsupportedMediaDownloader(this._reason);

  final String _reason;

  @override
  Stream<DownloadProgress> get onProgress =>
      const Stream<DownloadProgress>.empty();

  @override
  Stream<DownloadState> get onStateChanged =>
      const Stream<DownloadState>.empty();

  @override
  Stream<DownloadError> get onError => const Stream<DownloadError>.empty();

  @override
  Stream<LogMessage> get onLog => const Stream<LogMessage>.empty();

  @override
  Future<InitResult> initialize({
    bool enableFFmpeg = true,
    bool enableAria2c = false,
  }) async => InitResult(success: false, errorMessage: _reason);

  @override
  Future<UpdateResult> updateYoutubeDL({
    UpdateChannel channel = UpdateChannel.stable,
  }) async =>
      UpdateResult(status: OperationStatus.error, errorMessage: _reason);

  @override
  Future<VideoInfo> getVideoInfo(String url) async => throw StateError(_reason);

  @override
  Future<DownloadResult> download(DownloadRequest request) async =>
      DownloadResult(status: OperationStatus.error, errorMessage: _reason);

  @override
  Future<bool> cancelDownload(String processId) async => false;

  @override
  void dispose() {}
}

class _ActiveDownload {
  _ActiveDownload({required this.processId});
  final String processId;
  File? outputFile;
  File? artworkFile;
  AudioStreamTransfer? transfer;
  Directory? staging;
  final extractor = NativeAudioExtractor();
  Future<void> clearStaging() async {
    final directory = staging;
    staging = null;
    if (directory != null && await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  final Completer<void> cancellation = Completer<void>();
  final yt.YoutubeExplode youtube = yt.YoutubeExplode();
  bool get cancelled => cancellation.isCompleted;
  void cancel() {
    if (!cancelled) cancellation.complete();
    transfer?.cancel();
    unawaited(extractor.cancel(processId));
    youtube.close();
  }

  void checkCancelled() {
    if (cancelled) throw StateError('Download cancelled');
  }

  Future<T> waitFor<T>(Future<T> operation) => Future.any<T>([
    operation.timeout(const Duration(seconds: 25)),
    cancellation.future.then<T>((_) => throw StateError('Download cancelled')),
  ]);
}
