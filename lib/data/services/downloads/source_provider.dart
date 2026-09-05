/// Pluggable download-source abstraction for Monolith 2.0.
///
/// A [SourceProvider] knows how to fetch audio from one kind of source
/// (today: YouTube via `youtube_explode_dart`; tomorrow: anything else). The
/// [DownloadManager] is provider-agnostic — it only speaks this interface —
/// so adding a source never touches queue/persistence logic.
///
/// Contract notes:
/// - [inspect] is a cheap metadata lookup; it may run before the Wi-Fi-only
///   gate is satisfied (the actual byte transfer is what the gate protects).
/// - [download] reports progress through a single-subscription stream and
///   **must clean up partial files** when the consumer cancels the
///   subscription (YouTube streams are not resumable, so cancel + restart is
///   the honest pause/retry model).
library;

/// Metadata discovered before downloading.
class DownloadPreview {
  const DownloadPreview({
    required this.title,
    this.artist,
    this.durationMs,
    this.artworkUrl,
    required this.suggestedFileName,
  });

  final String title;
  final String? artist;

  /// Track duration in milliseconds; null when the source does not report it.
  final int? durationMs;

  /// Remote artwork URL, if the source exposes one.
  final String? artworkUrl;

  /// Provider-suggested file name (extension advisory only — the concrete
  /// container extension is only known once a stream is selected).
  final String suggestedFileName;
}

/// Everything a provider needs to perform one download.
class DownloadRequest {
  const DownloadRequest({
    required this.id,
    required this.sourceUri,
    required this.fileName,
  });

  /// Correlates the stream back to the manager's [DownloadTask].
  final String id;
  final Uri sourceUri;

  /// Sanitized base file name; the provider appends the real container
  /// extension of the selected stream.
  final String fileName;
}

/// Terminal/transient events emitted by [SourceProvider.download].
sealed class DownloadEvent {
  const DownloadEvent();
}

/// Byte-transfer progress. [total] may be 0 while the size is unknown.
class DownloadProgress extends DownloadEvent {
  const DownloadProgress({required this.received, required this.total});

  final int received;
  final int total;
}

/// The audio file is fully written to disk at [filePath].
class DownloadCompleted extends DownloadEvent {
  const DownloadCompleted({required this.filePath});

  final String filePath;
}

/// The download did not produce a usable file; [message] is user-facing.
class DownloadFailed extends DownloadEvent {
  const DownloadFailed({required this.message});

  final String message;
}

/// One downloadable source kind.
abstract interface class SourceProvider {
  /// Stable identifier used for logging/debugging.
  String get id;

  /// Resolves [source] into display metadata, or throws when this provider
  /// cannot handle the URI (the manager treats that as "try next provider").
  Future<DownloadPreview> inspect(Uri source);

  /// Streams the download. Single-subscription: exactly one consumer (the
  /// manager). Cancelling the subscription must remove any partial output.
  Stream<DownloadEvent> download(DownloadRequest req);
}
