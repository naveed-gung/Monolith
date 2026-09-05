import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:share_plus/share_plus.dart';

import '../../domain/models/track.dart';
import '../platform_channels/media_import_channel.dart';
import '../services/storage/library_store.dart';

/// Result of an export flow. [savedCount] is best-effort (the iOS document
/// picker only reports cancellation, not per-file success).
class ExportOutcome {
  const ExportOutcome({required this.savedCount, required this.canceled});

  final int savedCount;
  final bool canceled;
}

/// Injectable audio-file picker so tests can bypass the system dialog.
typedef AudioFilePicker = Future<List<XFile>> Function();

/// One-tap import/export/backup for Monolith 2.0.
///
/// - Import always **copies** files into `Music/Imports` — provider paths are
///   never referenced after the pick returns.
/// - Export routes to the native module on iOS (`exportToFiles`) and Android
///   (`exportToSaf`), falling back to the share sheet when the channel is
///   unavailable.
/// - Backup zips the whole `Music/` tree plus `manifest.json`; restore
///   re-imports a backup zip and merges it into the current library.
class ImportExportRepository {
  ImportExportRepository({
    required MediaImportChannel channel,
    required LibraryStore libraryStore,
    required Directory Function() tempDirProvider,
    AudioFilePicker? audioFilePicker,
  }) : _channel = channel,
       _libraryStore = libraryStore,
       _tempDirProvider = tempDirProvider,
       _audioFilePicker = audioFilePicker ?? _defaultAudioFilePicker;

  static const String _importsFolder = 'Imports';
  static const String _backupPrefix = 'monolith-backup';
  static const String _manifestZipEntry = 'manifest.json';

  final MediaImportChannel _channel;
  final LibraryStore _libraryStore;
  final Directory Function() _tempDirProvider;
  final AudioFilePicker _audioFilePicker;

  static const XTypeGroup _audioTypeGroup = XTypeGroup(
    label: 'audio',
    extensions: [
      'aac',
      'aiff',
      'alac',
      'amr',
      'flac',
      'm4a',
      'mp3',
      'mp4',
      'oga',
      'ogg',
      'opus',
      'wav',
      'weba',
      'webm',
    ],
    mimeTypes: ['audio/*'],
  );

  static Future<List<XFile>> _defaultAudioFilePicker() => openFiles(
    acceptedTypeGroups: [_audioTypeGroup],
    confirmButtonText: 'Import',
  );

  // ------------------------------------------------------------------
  // Import from files (document picker)
  // ------------------------------------------------------------------

  /// Opens the system audio picker and copies every picked file into
  /// `Music/Imports`, registering the copies in the manifest. Returns the
  /// newly imported tracks (empty when nothing was picked).
  Future<List<Track>> importFromFiles() async {
    final picked = await _audioFilePicker();
    if (picked.isEmpty) return const [];

    final importsDir = Directory(
      '${(await _libraryStore.musicDirectory()).path}/$_importsFolder',
    );
    await importsDir.create(recursive: true);

    final imported = <Track>[];
    for (final pickedFile in picked) {
      final sourcePath = pickedFile.path.trim().isEmpty
          ? null
          : pickedFile.path;
      final sourceBytes = sourcePath == null
          ? await pickedFile.readAsBytes()
          : null;
      // Some platforms return a name containing path fragments; normalize so
      // the stored copy always gets a clean file name.
      final displayName = fileNameOf(
        pickedFile.name.trim().isEmpty ? pickedFile.path : pickedFile.name,
      );
      final track = await _copyIntoLibrary(
        sourcePath: sourcePath,
        sourceBytes: sourceBytes,
        displayName: displayName,
        importsDir: importsDir,
      );
      if (track != null) imported.add(track);
    }

    if (imported.isEmpty) return const [];
    await _mergeIntoManifest(imported);
    return imported;
  }

  Future<Track?> _copyIntoLibrary({
    required String? sourcePath,
    required Uint8List? sourceBytes,
    required String displayName,
    required Directory importsDir,
  }) async {
    final safeName = sanitizeFileName(displayName);
    if (!LibraryStore.isAudioFile(safeName)) return null;

    final destPath = await _uniqueDestination(importsDir.path, safeName);
    try {
      if (sourcePath != null) {
        await File(sourcePath).copy(destPath);
      } else if (sourceBytes != null) {
        await File(destPath).writeAsBytes(sourceBytes, flush: true);
      } else {
        return null;
      }
    } on FileSystemException {
      // A single unreadable pick must not abort the whole batch; it is
      // simply skipped so the rest of the selection still lands.
      return null;
    }

    return Track(
      id: 'import-${LibraryStore.canonical(destPath).hashCode}',
      title: stemOf(safeName),
      artist: 'Unknown',
      album: 'Imports',
      filePath: destPath,
      source: TrackSource.imported,
      addedAt: DateTime.now(),
    );
  }

  // ------------------------------------------------------------------
  // Import from the music app (native picker; iOS)
  // ------------------------------------------------------------------

  /// Delegates to the native music-library picker and converts copied items
  /// into tracks. Protected/unavailable/failed items are skipped here — the
  /// UI layer surfaces their reasons via [MediaImportChannel.pickFromMusicLibrary].
  Future<List<Track>> importFromMusicApp() async {
    final results = await _channel.pickFromMusicLibrary();

    final tracks = <Track>[];
    for (final result in results) {
      if (result.status != ImportedItemStatus.copied) continue;
      final path = result.path;
      if (path == null || path.trim().isEmpty) continue;
      tracks.add(
        Track(
          id: 'import-${LibraryStore.canonical(path).hashCode}',
          title: result.title.isEmpty ? stemOf(fileNameOf(path)) : result.title,
          artist: result.artist.isEmpty ? 'Unknown' : result.artist,
          album: 'Imports',
          durationMs: result.durationMs,
          filePath: path,
          source: TrackSource.imported,
          addedAt: DateTime.now(),
        ),
      );
    }

    if (tracks.isNotEmpty) await _mergeIntoManifest(tracks);
    return tracks;
  }

  // ------------------------------------------------------------------
  // Export
  // ------------------------------------------------------------------

  /// Exports the given tracks' audio files through the platform-appropriate
  /// destination picker (Files/iCloud on iOS, SAF on Android), falling back
  /// to the share sheet when the native module is unavailable.
  Future<ExportOutcome> exportTracks(List<Track> tracks) async {
    final files = <File>[];
    for (final track in tracks) {
      if (track.filePath.trim().isEmpty) continue;
      final file = File(track.filePath);
      if (await file.exists()) files.add(file);
    }
    return _exportFiles(files);
  }

  Future<ExportOutcome> _exportFiles(List<File> files) async {
    if (files.isEmpty) {
      return const ExportOutcome(savedCount: 0, canceled: true);
    }
    final paths = files.map((file) => file.path).toList();

    if (!kIsWeb && Platform.isIOS) {
      try {
        final result = await _channel.exportToFiles(paths);
        return ExportOutcome(
          savedCount: result.canceled ? 0 : paths.length,
          canceled: result.canceled,
        );
      } on MissingPluginException {
        return _shareFallback(files);
      }
    }

    if (!kIsWeb && Platform.isAndroid) {
      try {
        final mimeTypes = paths
            .map((path) => mimeTypeForFileName(fileNameOf(path)))
            .toList();
        final result = await _channel.exportToSaf(paths, mimeTypes);
        return ExportOutcome(
          savedCount: result.savedCount,
          canceled: result.canceled,
        );
      } on MissingPluginException {
        return _shareFallback(files);
      }
    }

    return _shareFallback(files);
  }

  Future<ExportOutcome> _shareFallback(List<File> files) async {
    try {
      await Share.shareXFiles(
        files.map((file) => XFile(file.path)).toList(),
        text: 'Monolith export',
      );
      return ExportOutcome(savedCount: files.length, canceled: false);
    } catch (_) {
      // Share sheet unavailable or dismissed with an error; report as canceled.
      return const ExportOutcome(savedCount: 0, canceled: true);
    }
  }

  // ------------------------------------------------------------------
  // Backup / restore
  // ------------------------------------------------------------------

  /// Builds the backup zip (all audio under `Music/` + `manifest.json`) in
  /// the scratch directory, then routes it through the same export path as a
  /// single file. The [tracks] argument is advisory today — the archive
  /// intentionally contains the full Music tree so nothing is missed.
  Future<ExportOutcome> backupLibrary(List<Track> tracks) async {
    final zip = await buildBackupArchive(tracks);
    return _exportFiles([zip]);
  }

  /// Builds the backup zip without invoking any export UI. Exposed so tests
  /// (and future callers) can inspect or transport the archive directly.
  Future<File> buildBackupArchive(List<Track> tracks) async {
    final archive = Archive();

    final manifest = File(
      '${(await _libraryStore.rootDirectory()).path}/manifest.json',
    );
    if (await manifest.exists()) {
      archive.addFile(
        ArchiveFile.bytes(_manifestZipEntry, await manifest.readAsBytes()),
      );
    }

    final musicDir = await _libraryStore.musicDirectory();
    if (await musicDir.exists()) {
      await for (final entity in musicDir.list(recursive: true)) {
        if (entity is! File || !LibraryStore.isAudioFile(entity.path)) continue;
        final relative = LibraryStore.canonical(entity.path)
            .substring(LibraryStore.canonical(musicDir.path).length)
            .replaceFirst(RegExp(r'^/'), '');
        archive.addFile(
          ArchiveFile.bytes(relative, await entity.readAsBytes()),
        );
      }
    }

    final temp = _tempDirProvider();
    await temp.create(recursive: true);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final zipPath = '${temp.path}/$_backupPrefix-$stamp.zip';
    final encoded = ZipEncoder().encode(archive);
    return File(zipPath)..writeAsBytesSync(encoded, flush: true);
  }

  /// Restores a backup zip produced by [buildBackupArchive]: extracts to a
  /// scratch dir, re-imports the audio into `Music/Imports`, matches manifest
  /// entries by original basename (preserving title/artist/duration), merges
  /// everything into the current library and returns the restored tracks.
  Future<List<Track>> restoreBackup(String pickedZipPath) async {
    final bytes = await File(pickedZipPath).readAsBytes();

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } on FormatException {
      throw const FormatException('Not a valid Monolith backup zip.');
    }

    final stagingRoot = Directory(
      '${_tempDirProvider().path}/restore-${DateTime.now().millisecondsSinceEpoch}',
    );
    await stagingRoot.create(recursive: true);

    try {
      final manifestTracks = <Track>[];
      final stagedFiles = <File>[];

      for (final entry in archive.files) {
        if (!entry.isFile) continue;
        final name = entry.name.replaceAll('\\', '/');
        if (name.endsWith('/') || name.startsWith('__MACOSX')) continue;

        final data = entry.content as Uint8List?;
        if (data == null) continue;

        if (name == _manifestZipEntry) {
          manifestTracks.addAll(_parseManifestBytes(data));
          continue;
        }
        if (!LibraryStore.isAudioFile(name)) continue;

        final destPath = await _uniqueDestination(
          stagingRoot.path,
          sanitizeFileName(name.split('/').last),
        );
        final staged = File(destPath);
        await staged.writeAsBytes(data, flush: true);
        stagedFiles.add(staged);
      }

      final musicDir = await _libraryStore.musicDirectory();
      final importsDir = Directory('${musicDir.path}/$_importsFolder');
      await importsDir.create(recursive: true);

      // Match manifest entries to staged files by original basename so
      // metadata survives the absolute-path change across devices/installs.
      final byBaseName = <String, File>{
        for (final file in stagedFiles)
          fileNameOf(file.path).toLowerCase(): file,
      };

      final restored = <Track>[];
      final consumedPaths = <String>{};
      for (final manifestTrack in manifestTracks) {
        final match =
            byBaseName[fileNameOf(manifestTrack.filePath).toLowerCase()];
        if (match == null) continue;
        consumedPaths.add(LibraryStore.canonical(match.path));
        final newPath = await _adoptStagedFile(match, importsDir);
        restored.add(
          manifestTrack.copyWith(
            id: 'import-${LibraryStore.canonical(newPath).hashCode}',
            filePath: newPath,
            source: TrackSource.imported,
          ),
        );
      }
      for (final staged in stagedFiles) {
        if (consumedPaths.contains(LibraryStore.canonical(staged.path))) {
          continue;
        }
        final newPath = await _adoptStagedFile(staged, importsDir);
        restored.add(
          Track(
            id: 'import-${LibraryStore.canonical(newPath).hashCode}',
            title: stemOf(fileNameOf(newPath)),
            artist: 'Unknown',
            album: 'Restored',
            filePath: newPath,
            source: TrackSource.imported,
            addedAt: DateTime.now(),
          ),
        );
      }

      if (restored.isNotEmpty) await _mergeIntoManifest(restored);
      return restored;
    } finally {
      try {
        if (await stagingRoot.exists()) {
          await stagingRoot.delete(recursive: true);
        }
      } on FileSystemException catch (_) {
        // Best-effort cleanup; leftover staging files are harmless.
      }
    }
  }

  Future<String> _adoptStagedFile(File staged, Directory importsDir) async {
    final destPath = await _uniqueDestination(
      importsDir.path,
      fileNameOf(staged.path),
    );
    try {
      await staged.rename(destPath);
    } on FileSystemException {
      // Cross-volume fallback: copy instead of move.
      await staged.copy(destPath);
    }
    return destPath;
  }

  List<Track> _parseManifestBytes(Uint8List bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      final List<dynamic> rawTracks;
      if (decoded is Map<String, dynamic>) {
        rawTracks = decoded['tracks'] as List<dynamic>? ?? const [];
      } else if (decoded is List<dynamic>) {
        rawTracks = decoded;
      } else {
        return const [];
      }
      return [
        for (final item in rawTracks)
          if (item is Map<String, dynamic>) Track.fromJson(item),
      ];
    } on FormatException catch (_) {
      // A corrupt manifest inside a backup must not crash the restore;
      // unmatched audio files are still recovered below.
      return const [];
    }
  }

  // ------------------------------------------------------------------
  // Shared helpers
  // ------------------------------------------------------------------

  Future<void> _mergeIntoManifest(List<Track> additions) async {
    final existing = await _libraryStore.load();
    final knownPaths = existing
        .map((t) => LibraryStore.canonical(t.filePath))
        .toSet();
    final merged = [
      ...existing,
      ...additions.where(
        (t) => !knownPaths.contains(LibraryStore.canonical(t.filePath)),
      ),
    ];
    await _libraryStore.save(merged);
  }

  Future<String> _uniqueDestination(String dirPath, String fileName) async {
    final candidate = '$dirPath/$fileName';
    if (!await File(candidate).exists()) return candidate;
    final ext = extensionOf(fileName);
    final suffix = ext.isEmpty ? '' : '.$ext';
    return '$dirPath/${stemOf(fileName)}-${DateTime.now().microsecondsSinceEpoch}$suffix';
  }

  static String fileNameOf(String path) {
    final normalized = path.replaceAll('\\', '/');
    final slashIndex = normalized.lastIndexOf('/');
    return slashIndex == -1 ? normalized : normalized.substring(slashIndex + 1);
  }

  static String extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  static String stemOf(String name) {
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? name : name.substring(0, dot);
  }

  static String sanitizeFileName(String raw) {
    var cleaned = raw.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    cleaned = cleaned.replaceAll(RegExp(r'[\x00-\x1f]'), '_').trim();
    if (cleaned.isEmpty) cleaned = 'audio';
    return cleaned.length > 120 ? cleaned.substring(0, 120) : cleaned;
  }

  static String mimeTypeForFileName(String name) {
    switch (extensionOf(name)) {
      case 'mp3':
        return 'audio/mpeg';
      case 'm4a':
      case 'mp4':
        return 'audio/mp4';
      case 'aac':
        return 'audio/aac';
      case 'flac':
        return 'audio/flac';
      case 'wav':
        return 'audio/x-wav';
      case 'ogg':
      case 'oga':
      case 'opus':
        return 'audio/ogg';
      case 'webm':
      case 'weba':
        return 'audio/webm';
      case 'aiff':
      case 'aif':
        return 'audio/aiff';
      default:
        return 'application/octet-stream';
    }
  }
}
