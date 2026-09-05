/// Lifecycle state of a download.
enum DownloadTaskState { queued, running, paused, failed, completed, canceled }

/// An in-flight or finished download, decoupled from any concrete downloader
/// implementation (the SourceProvider interface lands in a later phase).
///
/// Pure Dart and immutable; progress updates flow through [copyWith].
class DownloadTask {
  const DownloadTask({
    required this.id,
    required this.sourceUri,
    required this.title,
    required this.fileName,
    this.state = DownloadTaskState.queued,
    this.progressBytes = 0,
    this.totalBytes = 0,
    this.errorMessage,
    required this.createdAt,
  });

  final String id;

  /// The URI the content is fetched from.
  final String sourceUri;
  final String title;

  /// Target file name inside the Music directory.
  final String fileName;
  final DownloadTaskState state;

  /// Bytes received so far.
  final int progressBytes;

  /// Expected total size; 0 means unknown.
  final int totalBytes;

  /// Populated when [state] is [DownloadTaskState.failed].
  final String? errorMessage;
  final DateTime createdAt;

  DownloadTask copyWith({
    String? id,
    String? sourceUri,
    String? title,
    String? fileName,
    DownloadTaskState? state,
    int? progressBytes,
    int? totalBytes,
    String? errorMessage,
    DateTime? createdAt,
  }) {
    return DownloadTask(
      id: id ?? this.id,
      sourceUri: sourceUri ?? this.sourceUri,
      title: title ?? this.title,
      fileName: fileName ?? this.fileName,
      state: state ?? this.state,
      progressBytes: progressBytes ?? this.progressBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Stable JSON keys so task queues survive restarts (persisted by the
  /// download repository in a later phase). Dates serialize as ISO-8601.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'sourceUri': sourceUri,
      'title': title,
      'fileName': fileName,
      'state': state.name,
      'progressBytes': progressBytes,
      'totalBytes': totalBytes,
      'errorMessage': errorMessage,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    return DownloadTask(
      id: json['id'] as String? ?? '',
      sourceUri: json['sourceUri'] as String? ?? '',
      title: json['title'] as String? ?? '',
      fileName: json['fileName'] as String? ?? '',
      state:
          DownloadTaskState.values.asNameMap()[json['state'] as String?] ??
          DownloadTaskState.queued,
      progressBytes: (json['progressBytes'] as num?)?.toInt() ?? 0,
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      errorMessage: json['errorMessage'] as String?,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DownloadTask &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          sourceUri == other.sourceUri &&
          title == other.title &&
          fileName == other.fileName &&
          state == other.state &&
          progressBytes == other.progressBytes &&
          totalBytes == other.totalBytes &&
          errorMessage == other.errorMessage &&
          createdAt == other.createdAt;

  @override
  int get hashCode => Object.hash(
    id,
    sourceUri,
    title,
    fileName,
    state,
    progressBytes,
    totalBytes,
    errorMessage,
    createdAt,
  );

  @override
  String toString() => 'DownloadTask($id, $state, $progressBytes/$totalBytes)';
}
