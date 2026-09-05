import 'package:flutter/services.dart';

/// Typed bridge to the native `monolith/media_import` module
/// (iOS: `ios/Runner/MediaImport/MediaImportPlugin.swift`,
/// Android: `MediaImportHandler.kt`).
///
/// [PlatformException]s are converted into graceful defaults (empty results /
/// canceled exports) so a native hiccup never crashes the app;
/// [MissingPluginException] is deliberately rethrown so callers can fall back
/// to share-sheet based export on platforms without the native module.
class MediaImportChannel {
  /// Injectable for tests; defaults to the production channel.
  MediaImportChannel({MethodChannel? channel})
    : channel = channel ?? const MethodChannel('monolith/media_import');

  final MethodChannel channel;

  /// Presents the iOS music-library picker and copies readable items into
  /// the app sandbox. Returns one result per picked item.
  Future<List<ImportedItemResult>> pickFromMusicLibrary() async {
    try {
      final raw = await channel.invokeMethod<Object?>('pickFromMusicLibrary');
      if (raw is! List) return const [];
      return [
        for (final entry in raw)
          if (entry is Map) ImportedItemResult.fromMap(entry),
      ];
    } on PlatformException {
      rethrow;
    }
  }

  /// Save-to-Files export (iOS document picker, asCopy). The native side only
  /// reports whether the flow was canceled.
  Future<ExportResult> exportToFiles(List<String> paths) async {
    try {
      final map = await channel.invokeMapMethod<String, Object?>(
        'exportToFiles',
        <String, Object?>{'paths': paths},
      );
      return ExportResult.fromMap(map);
    } on PlatformException {
      return const ExportResult(savedCount: 0, canceled: true);
    }
  }

  /// Sequential SAF export (Android ACTION_CREATE_DOCUMENT per file).
  Future<ExportResult> exportToSaf(
    List<String> paths,
    List<String> mimeTypes,
  ) async {
    try {
      final map = await channel.invokeMapMethod<String, Object?>(
        'exportToSaf',
        <String, Object?>{'paths': paths, 'mimeTypes': mimeTypes},
      );
      return ExportResult.fromMap(map);
    } on PlatformException {
      return const ExportResult(savedCount: 0, canceled: true);
    }
  }

  /// Copies one file into public Music/Monolith via MediaStore (Android Q+)
  /// or the legacy public directory. Never throws; inspect [PublicWriteResult].
  Future<PublicWriteResult> writeToPublicMusic(String path) async {
    try {
      final map = await channel.invokeMapMethod<String, Object?>(
        'writeToPublicMusic',
        <String, Object?>{'path': path},
      );
      return PublicWriteResult(
        uri: map?['uri'] as String?,
        error: map?['error'] as String?,
      );
    } on PlatformException catch (e) {
      return PublicWriteResult(error: e.message ?? e.code);
    }
  }

  /// Absolute path of `Documents/Monolith/Music` (iOS), or null on failure.
  Future<String?> getDocumentsMusicPath() async {
    try {
      return await channel.invokeMethod<String>('getDocumentsMusicPath');
    } on PlatformException {
      return null;
    }
  }

  /// Best-effort absolute path of public Music/Monolith (Android), or null.
  Future<String?> getPublicMusicDir() async {
    try {
      return await channel.invokeMethod<String>('getPublicMusicDir');
    } on PlatformException {
      return null;
    }
  }
}

/// Outcome of one item handed back by the native music-library picker.
enum ImportedItemStatus { copied, protected, unavailable, failed }

class ImportedItemResult {
  const ImportedItemResult({
    required this.status,
    this.path,
    this.title = '',
    this.artist = '',
    this.reason,
    this.durationMs = 0,
  });

  factory ImportedItemResult.fromMap(Map<dynamic, dynamic> map) {
    return ImportedItemResult(
      status: _decodeStatus(map['status'] as String?),
      path: map['path'] as String?,
      title: map['title'] as String? ?? '',
      artist: map['artist'] as String? ?? '',
      reason: map['reason'] as String?,
      durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
    );
  }

  static ImportedItemStatus _decodeStatus(String? name) {
    switch (name) {
      case 'copied':
        return ImportedItemStatus.copied;
      case 'protected':
        return ImportedItemStatus.protected;
      case 'unavailable':
        return ImportedItemStatus.unavailable;
      // Unknown names and 'failed' land here so callers can show a generic
      // failure message instead of crashing on future status values.
      default:
        return ImportedItemStatus.failed;
    }
  }

  final ImportedItemStatus status;

  /// Sandbox path of the copied audio file; only set when status == copied.
  final String? path;
  final String title;
  final String artist;
  final String? reason;

  /// Duration in milliseconds; 0 = unknown.
  final int durationMs;
}

class ExportResult {
  const ExportResult({required this.savedCount, required this.canceled});

  factory ExportResult.fromMap(Map<Object?, Object?>? map) {
    return ExportResult(
      savedCount: (map?['savedCount'] as num?)?.toInt() ?? 0,
      canceled: map?['canceled'] as bool? ?? false,
    );
  }

  final int savedCount;
  final bool canceled;
}

class PublicWriteResult {
  const PublicWriteResult({this.uri, this.error});

  final String? uri;
  final String? error;

  bool get succeeded => uri != null && error == null;
}
