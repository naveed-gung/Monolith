import 'package:flutter/material.dart';

enum AppTab { library, downloads, search }

enum LibraryCategory { tracks, artists, albums, playlists }

enum RepeatMode { off, all, one }

enum ThemePreference { system, light, dark }

enum TrackSource { mock, device, downloaded, imported }

enum DownloadTaskStatus {
  ready,
  downloading,
  paused,
  completed,
  failed,
  cancelled,
}

class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.genre,
    required this.duration,
    required this.colors,
    required this.blurb,
    required this.source,
    this.filePath,
    this.artworkQueryId,
    this.artworkFilePath,
    this.artworkUrl,
  });

  final String id;
  final String title;
  final String artist;
  final String album;
  final String genre;
  final Duration duration;
  final List<Color> colors;
  final String blurb;
  final TrackSource source;
  final String? filePath;
  final int? artworkQueryId;
  final String? artworkFilePath;
  final String? artworkUrl;

  bool get canPlay => filePath != null && filePath!.isNotEmpty;

  Track copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    String? genre,
    Duration? duration,
    List<Color>? colors,
    String? blurb,
    TrackSource? source,
    String? filePath,
    int? artworkQueryId,
    String? artworkFilePath,
    String? artworkUrl,
  }) {
    return Track(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      genre: genre ?? this.genre,
      duration: duration ?? this.duration,
      colors: colors ?? this.colors,
      blurb: blurb ?? this.blurb,
      source: source ?? this.source,
      filePath: filePath ?? this.filePath,
      artworkQueryId: artworkQueryId ?? this.artworkQueryId,
      artworkFilePath: artworkFilePath ?? this.artworkFilePath,
      artworkUrl: artworkUrl ?? this.artworkUrl,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'genre': genre,
      'durationMs': duration.inMilliseconds,
      'colors': colors.map((color) => color.toARGB32()).toList(),
      'blurb': blurb,
      'source': source.name,
      'filePath': filePath,
      'artworkQueryId': artworkQueryId,
      'artworkFilePath': artworkFilePath,
      'artworkUrl': artworkUrl,
    };
  }

  factory Track.fromJson(Map<String, dynamic> json) {
    return Track(
      id: json['id'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String,
      album: json['album'] as String,
      genre: json['genre'] as String? ?? 'Downloaded audio',
      duration: Duration(milliseconds: json['durationMs'] as int? ?? 0),
      colors: (json['colors'] as List<dynamic>? ?? const [])
          .map((value) => Color(value as int))
          .toList(),
      blurb: json['blurb'] as String? ?? '',
      source: TrackSource.values.byName(
        json['source'] as String? ?? TrackSource.mock.name,
      ),
      filePath: json['filePath'] as String?,
      artworkQueryId: json['artworkQueryId'] as int?,
      artworkFilePath: json['artworkFilePath'] as String?,
      artworkUrl: json['artworkUrl'] as String?,
    );
  }

  static List<Color> paletteForSeed(String seed) {
    final hash = seed.codeUnits.fold<int>(
      0,
      (value, rune) => value * 31 + rune,
    );
    Color tone(double offset, double saturation, double lightness) {
      final hue = ((hash % 360) + offset) % 360;
      return HSLColor.fromAHSL(1, hue, saturation, lightness).toColor();
    }

    return [tone(0, 0.72, 0.66), tone(28, 0.58, 0.44), tone(96, 0.42, 0.18)];
  }
}

class DownloadPreview {
  const DownloadPreview({
    required this.url,
    required this.title,
    required this.suggestedFileName,
    this.uploader,
    this.thumbnailUrl,
    this.duration,
    this.estimatedSizeBytes,
  });

  final String url;
  final String title;
  final String suggestedFileName;
  final String? uploader;
  final String? thumbnailUrl;
  final Duration? duration;
  final int? estimatedSizeBytes;
}

class DownloadTaskInfo {
  const DownloadTaskInfo({
    required this.processId,
    required this.url,
    required this.title,
    required this.fileName,
    required this.status,
    this.uploader,
    this.thumbnailUrl,
    this.progress = 0,
    this.eta = Duration.zero,
    this.errorMessage,
    this.outputPath,
    this.mediaDuration,
    this.totalBytes,
    this.downloadSpeedBytesPerSecond,
    this.detailLog,
  });

  final String processId;
  final String url;
  final String title;
  final String fileName;
  final DownloadTaskStatus status;
  final String? uploader;
  final String? thumbnailUrl;
  final double progress;
  final Duration eta;
  final String? errorMessage;
  final String? outputPath;
  final Duration? mediaDuration;
  final int? totalBytes;
  final int? downloadSpeedBytesPerSecond;
  final String? detailLog;

  bool get isActive =>
      status == DownloadTaskStatus.ready ||
      status == DownloadTaskStatus.downloading;

  bool get canPause => status == DownloadTaskStatus.downloading;

  bool get canResume => status == DownloadTaskStatus.paused;

  bool get canRetry =>
      status == DownloadTaskStatus.failed ||
      status == DownloadTaskStatus.cancelled;

  int? get downloadedBytes {
    if (totalBytes == null) {
      return null;
    }
    return (totalBytes! * progress.clamp(0.0, 1.0)).round();
  }

  String? get latestDetailLine {
    final rawLog = detailLog;
    if (rawLog == null || rawLog.trim().isEmpty) {
      return null;
    }

    final lines = rawLog
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);

    if (lines.isEmpty) {
      return null;
    }

    return lines.last;
  }

  String get statusLabel {
    switch (status) {
      case DownloadTaskStatus.ready:
        return 'Ready';
      case DownloadTaskStatus.downloading:
        return 'Downloading';
      case DownloadTaskStatus.paused:
        return 'Paused';
      case DownloadTaskStatus.completed:
        return 'Completed';
      case DownloadTaskStatus.failed:
        return 'Failed';
      case DownloadTaskStatus.cancelled:
        return 'Cancelled';
    }
  }

  DownloadTaskInfo copyWith({
    String? processId,
    String? url,
    String? title,
    String? fileName,
    DownloadTaskStatus? status,
    String? uploader,
    String? thumbnailUrl,
    double? progress,
    Duration? eta,
    String? errorMessage,
    String? outputPath,
    Duration? mediaDuration,
    int? totalBytes,
    int? downloadSpeedBytesPerSecond,
    String? detailLog,
  }) {
    return DownloadTaskInfo(
      processId: processId ?? this.processId,
      url: url ?? this.url,
      title: title ?? this.title,
      fileName: fileName ?? this.fileName,
      status: status ?? this.status,
      uploader: uploader ?? this.uploader,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      progress: progress ?? this.progress,
      eta: eta ?? this.eta,
      errorMessage: errorMessage ?? this.errorMessage,
      outputPath: outputPath ?? this.outputPath,
      mediaDuration: mediaDuration ?? this.mediaDuration,
      totalBytes: totalBytes ?? this.totalBytes,
      downloadSpeedBytesPerSecond:
          downloadSpeedBytesPerSecond ?? this.downloadSpeedBytesPerSecond,
      detailLog: detailLog ?? this.detailLog,
    );
  }
}
