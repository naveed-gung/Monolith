class DownloadProgress {
  DownloadProgress({
    required this.processId,
    required this.progress,
    required this.etaInSeconds,
  });

  final String processId;
  final double progress;
  final int etaInSeconds;

  double get progressFraction => progress / 100.0;

  Duration get eta => Duration(seconds: etaInSeconds);
}

class DownloadState {
  DownloadState({required this.processId, required this.state});

  final String processId;
  final DownloadStateType state;
}

enum DownloadStateType { started, completed, cancelled, unknown }

enum UpdateChannel { stable }

enum OperationStatus { success, error, cancelled }

class InitResult {
  InitResult({required this.success, this.errorMessage});

  final bool success;
  final String? errorMessage;
}

class UpdateResult {
  UpdateResult({required this.status, this.version, this.errorMessage});

  final OperationStatus status;
  final String? version;
  final String? errorMessage;
}

class VideoFormat {
  VideoFormat({
    this.formatId,
    this.formatNote,
    this.ext,
    this.url,
    this.width,
    this.height,
    this.fps,
    this.filesize,
    this.tbr,
    this.vcodec,
    this.acodec,
    this.resolution,
  });

  final String? formatId;
  final String? formatNote;
  final String? ext;
  final String? url;
  final int? width;
  final int? height;
  final int? fps;
  final int? filesize;
  final int? tbr;
  final String? vcodec;
  final String? acodec;
  final String? resolution;
}

class VideoInfo {
  VideoInfo({
    this.id,
    this.title,
    this.description,
    this.uploader,
    this.uploaderId,
    this.uploaderUrl,
    this.channelId,
    this.channelUrl,
    this.duration,
    this.viewCount,
    this.likeCount,
    this.thumbnail,
    this.url,
    this.formats,
    this.ext,
    this.width,
    this.height,
    this.fps,
    this.vcodec,
    this.acodec,
  });

  final String? id;
  final String? title;
  final String? description;
  final String? uploader;
  final String? uploaderId;
  final String? uploaderUrl;
  final String? channelId;
  final String? channelUrl;
  final int? duration;
  final int? viewCount;
  final int? likeCount;
  final String? thumbnail;
  final String? url;
  final List<VideoFormat>? formats;
  final String? ext;
  final int? width;
  final int? height;
  final int? fps;
  final String? vcodec;
  final String? acodec;
}

class DownloadRequest {
  DownloadRequest({
    required this.url,
    required this.outputPath,
    this.outputTemplate,
    this.format,
    this.noPlaylist,
    this.extractAudio,
    this.audioFormat,
    this.audioQuality,
    this.embedThumbnail,
    this.embedMetadata,
    this.embedSubtitles,
    this.subtitlesLang,
    this.writeSubtitles,
    this.writeAutoSubtitles,
    this.customOptions,
    this.processId,
  });

  final String url;
  final String outputPath;
  final String? outputTemplate;
  final String? format;
  final bool? noPlaylist;
  final bool? extractAudio;
  final String? audioFormat;
  final int? audioQuality;
  final bool? embedThumbnail;
  final bool? embedMetadata;
  final bool? embedSubtitles;
  final String? subtitlesLang;
  final bool? writeSubtitles;
  final bool? writeAutoSubtitles;
  final Map<String?, String?>? customOptions;
  final String? processId;
}

class DownloadResult {
  DownloadResult({required this.status, this.outputPath, this.errorMessage});

  final OperationStatus status;
  final String? outputPath;
  final String? errorMessage;
}

class DownloadError {
  DownloadError({required this.processId, required this.error});

  final String processId;
  final String error;
}

class LogMessage {
  LogMessage({
    required this.processId,
    required this.message,
    required this.level,
    required this.timestamp,
  });

  final String processId;
  final String message;
  final LogLevel level;
  final DateTime timestamp;
}

enum LogLevel { info, warning, error, debug }
