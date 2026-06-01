import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

import 'media_downloader_models.dart';

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

  static final List<yt.YoutubeApiClient> _preferredClients =
      <yt.YoutubeApiClient>[
        yt.YoutubeApiClient.ios,
        yt.YoutubeApiClient.androidVr,
      ];

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

    final video = await _youtube.videos.get(url);
    final manifest = await _youtube.videos.streams.getManifest(
      video.id,
      ytClients: _preferredClients,
    );
    final streams = manifest.audioOnly.toList();
    final preferredStream = _selectAudioStream(streams);

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
      formats: streams.map(_toVideoFormat).toList(growable: false),
      ext: preferredStream == null
          ? null
          : _audioExtension(preferredStream.container),
      acodec: preferredStream?.audioCodec,
    );
  }

  @override
  Future<DownloadResult> download(DownloadRequest request) async {
    await _ensureInitialized();

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
      _emitState(processId, DownloadStateType.started);
      _log(processId, 'Inspecting available YouTube audio streams.');

      final video = await _youtube.videos.get(request.url);
      final manifest = await _youtube.videos.streams.getManifest(
        video.id,
        ytClients: _preferredClients,
      );
      final selectedStream = _selectAudioStream(manifest.audioOnly);
      if (selectedStream == null) {
        throw StateError(
          'No downloadable audio stream was found for this video.',
        );
      }

      final outputFile = await _prepareOutputFile(
        request: request,
        video: video,
        stream: selectedStream,
      );
      activeDownload.outputFile = outputFile;
      activeDownload.artworkFile = request.embedThumbnail == true
          ? File('${_fileStem(outputFile.path)}.jpg')
          : null;
      activeDownload.sink = outputFile.openWrite();
      activeDownload.completer = Completer<DownloadResult>();

      _emitProgress(
        processId: processId,
        downloadedBytes: 0,
        totalBytes: selectedStream.size.totalBytes,
        elapsed: Duration.zero,
      );

      final stopwatch = Stopwatch()..start();
      var downloadedBytes = 0;

      activeDownload.subscription = _youtube.videos.streams
          .get(selectedStream)
          .listen(
            (chunk) {
              if (activeDownload.cancelled || activeDownload.sink == null) {
                return;
              }

              activeDownload.sink!.add(chunk);
              downloadedBytes += chunk.length;
              _emitProgress(
                processId: processId,
                downloadedBytes: downloadedBytes,
                totalBytes: selectedStream.size.totalBytes,
                elapsed: stopwatch.elapsed,
              );
            },
            onError: (Object error, StackTrace stackTrace) async {
              await activeDownload.closeSink();
              await _deletePartialFiles(activeDownload);
              final message = _normalizeDownloadError(error);
              _emitError(processId, message);
              activeDownload.complete(
                DownloadResult(
                  status: OperationStatus.error,
                  errorMessage: message,
                ),
              );
            },
            onDone: () async {
              await activeDownload.closeSink();

              if (activeDownload.cancelled) {
                await _deletePartialFiles(activeDownload);
                _emitState(processId, DownloadStateType.cancelled);
                activeDownload.complete(
                  DownloadResult(status: OperationStatus.cancelled),
                );
                return;
              }

              if (request.embedThumbnail == true) {
                await _downloadThumbnail(
                  video: video,
                  destination: activeDownload.artworkFile,
                  processId: processId,
                );
              }

              _emitProgress(
                processId: processId,
                downloadedBytes: selectedStream.size.totalBytes,
                totalBytes: selectedStream.size.totalBytes,
                elapsed: stopwatch.elapsed,
              );
              _emitState(processId, DownloadStateType.completed);
              activeDownload.complete(
                DownloadResult(
                  status: OperationStatus.success,
                  outputPath: outputFile.path,
                ),
              );
            },
            cancelOnError: true,
          );

      return await activeDownload.completer!.future;
    } catch (error) {
      await activeDownload.closeSink();
      await _deletePartialFiles(activeDownload);
      final message = _normalizeDownloadError(error);
      _emitError(processId, message);
      return DownloadResult(
        status: OperationStatus.error,
        errorMessage: message,
      );
    } finally {
      _activeDownloads.remove(processId);
    }
  }

  @override
  Future<bool> cancelDownload(String processId) async {
    final activeDownload = _activeDownloads[processId];
    if (activeDownload == null) {
      return false;
    }

    activeDownload.cancelled = true;
    await activeDownload.subscription?.cancel();
    await activeDownload.closeSink();
    await _deletePartialFiles(activeDownload);
    _emitState(processId, DownloadStateType.cancelled);
    activeDownload.complete(DownloadResult(status: OperationStatus.cancelled));
    return true;
  }

  @override
  void dispose() {
    for (final activeDownload in _activeDownloads.values) {
      activeDownload.cancelled = true;
      unawaited(activeDownload.subscription?.cancel());
      unawaited(activeDownload.closeSink());
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
      return 'The source blocked this download request (403 / anti-bot challenge), so Monolith stopped it before saving anything.';
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
      return mp4Streams.withHighestBitrate();
    }

    final directStreams = streamList
        .where((stream) => stream.container != yt.StreamContainer.m3u8)
        .toList(growable: false);
    if (directStreams.isNotEmpty) {
      return directStreams.withHighestBitrate();
    }

    return streamList.withHighestBitrate();
  }

  VideoFormat _toVideoFormat(yt.AudioOnlyStreamInfo stream) {
    return VideoFormat(
      formatId: '${stream.tag}',
      formatNote: stream.qualityLabel,
      ext: _audioExtension(stream.container),
      url: stream.url.toString(),
      filesize: stream.size.totalBytes,
      tbr: stream.bitrate.kiloBitsPerSecond.round(),
      vcodec: 'none',
      acodec: stream.audioCodec,
      resolution: 'audio only',
    );
  }

  Future<File> _prepareOutputFile({
    required DownloadRequest request,
    required yt.Video video,
    required yt.AudioOnlyStreamInfo stream,
  }) async {
    final outputDirectory = Directory(request.outputPath);
    if (!await outputDirectory.exists()) {
      await outputDirectory.create(recursive: true);
    }

    final baseName = _requestedBaseName(request.outputTemplate, video.title);
    final extension = _audioExtension(stream.container);
    final outputFile = File(
      '${outputDirectory.path}${Platform.pathSeparator}$baseName.$extension',
    );
    if (await outputFile.exists()) {
      await outputFile.delete();
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
      final response = await _httpClient.get(Uri.parse(_thumbnailUrl(video)));
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
    _progressController.add(
      DownloadProgress(
        processId: processId,
        progress: progress,
        etaInSeconds: eta,
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
  IOSink? sink;
  StreamSubscription<List<int>>? subscription;
  Completer<DownloadResult>? completer;
  bool cancelled = false;
  bool _sinkClosed = false;

  Future<void> closeSink() async {
    if (_sinkClosed) {
      return;
    }

    _sinkClosed = true;
    final currentSink = sink;
    sink = null;
    if (currentSink == null) {
      return;
    }

    await currentSink.flush();
    await currentSink.close();
  }

  void complete(DownloadResult result) {
    final currentCompleter = completer;
    if (currentCompleter == null || currentCompleter.isCompleted) {
      return;
    }

    currentCompleter.complete(result);
  }
}
