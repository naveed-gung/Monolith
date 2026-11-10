import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../../domain/models/track.dart';

/// Resolves the directory that owns Monolith's on-disk data. Injectable so
/// tests can point the store at a temporary directory.
typedef RootDirFactory = Future<Directory> Function();

/// Library persistence v2.
///
/// Manifest schema (`<root>/manifest.json`):
/// ```json
/// {"schemaVersion": 2, "tracks": [...], "savedAt": "2026-01-01T00:00:00.000Z"}
/// ```
///
/// Guarantees:
/// - **Atomic writes** — content goes to a temp file first, then renames over
///   the target, so a crash mid-write can never truncate the manifest.
/// - **Pruning on load** — entries whose audio file no longer exists are
///   dropped (and the prune persisted).
/// - **Disk-merge re-discovery** — audio files present under `Music/` but
///   missing from the manifest are re-added with best-effort metadata
///   (filename → title, mtime → addedAt) using stable path-hash ids, then the
///   merged list is persisted.
/// - **v1 migration** — a bare JSON array (the v1 [DownloadStore] shape) is
///   parsed into v2 models and re-saved in the v2 envelope on first load.
class LibraryStore {
  LibraryStore({RootDirFactory? rootDirFactory, RootDirFactory? audioDirFactory})
    : _rootDirFactory = rootDirFactory ?? defaultRootDirectory,
      _audioDirFactory = audioDirFactory;

  final RootDirFactory _rootDirFactory;
  final RootDirFactory? _audioDirFactory;

  /// Current manifest schema version.
  static const int schemaVersion = 2;

  /// Audio container extensions recognised during disk re-discovery
  /// (mirrors the v1 set exactly).
  static const Set<String> audioExtensions = {
    'mp3',
    'm4a',
    'aac',
    'flac',
    'wav',
    'ogg',
    'opus',
    'webm',
    'mp4',
  };

  static const String _musicFolderName = 'Music';
  static const String _manifestFileName = 'manifest.json';
  static const List<String> _artworkExtensions = ['jpg', 'jpeg', 'png', 'webp'];

  /// Default base-directory resolver — mirrors the v1
  /// `DownloadStore._rootDirectory` logic so both generations read/write the
  /// same location: Android → `<externalStorageDirectory>/Monolith`, else
  /// `<Documents>/Monolith`.
  static Future<Directory> defaultRootDirectory() async {
    if (Platform.isAndroid) {
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        return ensureDir('${extDir.path}/Monolith');
      }
    }
    final documents = await getApplicationDocumentsDirectory();
    return ensureDir('${documents.path}/Monolith');
  }

  /// Default audio-root resolver — mirrors the v1
  /// `DownloadStore._audioRootDirectory` logic: Android → public
  /// `Music/Monolith` (survives uninstall), else the private root.
  static Future<Directory> defaultAudioRootDirectory() async {
    if (Platform.isAndroid) {
      try {
        final path = await const MethodChannel(
          'monolith/media_import',
        ).invokeMethod<String>('getPublicMusicDir');
        if (path != null && path.isNotEmpty) {
          return ensureDir(path);
        }
      } catch (_) {
        // Fall through to the private root.
      }
    }
    return defaultRootDirectory();
  }

  /// Monolith's own private top-level data folder (manifest, artwork
  /// sidecars, pre-1.5.1 audio).
  Future<Directory> rootDirectory() => _rootDirFactory();

  /// The audio storage root — public `Music/Monolith` on Android when
  /// available, the private root otherwise.
  Future<Directory> audioRootDirectory() async {
    final factory = _audioDirFactory;
    if (factory == null) return rootDirectory();
    return factory();
  }

  /// The `Music` subfolder where audio lives; created on demand.
  Future<Directory> musicDirectory() async {
    final root = await audioRootDirectory();
    return ensureDir('${root.path}/$_musicFolderName');
  }

  /// Artwork sidecars for public audio live in the private `Art` folder:
  /// scoped storage (API 30+) can refuse non-media files in Music/.
  Future<Directory> _artDirectory() async {
    final root = await rootDirectory();
    return ensureDir('${root.path}/Art');
  }

  /// Loads the manifest, migrating from v1 if needed and pruning entries
  /// whose audio file is gone. Returns an empty list when no library exists.
  Future<List<Track>> load() async {
    final manifest = await _manifestFile();
    if (!await manifest.exists()) {
      return const [];
    }

    final raw = await manifest.readAsString();
    if (raw.trim().isEmpty) {
      return const [];
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      // A corrupt manifest must not take the library down; disk-merge can
      // still rebuild from surviving files.
      return const [];
    }

    var needsRewrite = false;
    List<dynamic> rawTracks;
    if (decoded is List<dynamic>) {
      // v1 shape: a bare JSON array of track objects.
      rawTracks = decoded;
      needsRewrite = true;
    } else if (decoded is Map<String, dynamic>) {
      rawTracks = decoded['tracks'] as List<dynamic>? ?? const [];
      needsRewrite = (decoded['schemaVersion'] as int? ?? 0) != schemaVersion;
    } else {
      return const [];
    }

    final tracks = <Track>[];
    for (final item in rawTracks) {
      if (item is! Map<String, dynamic>) continue;
      var track = Track.fromJson(item);
      // Pre-1.5.1 manifest paths point at the private root; audio moved to
      // public Music/Monolith — repoint before the existence check prunes.
      final relocated = await _relocatedPath(track.filePath);
      if (relocated != track.filePath) {
        track = track.copyWith(
          filePath: relocated,
          artworkPath: await findArtworkForAudio(relocated),
        );
        needsRewrite = true;
      }
      if (await _audioFileExists(track.filePath)) {
        tracks.add(track);
      }
    }

    if (needsRewrite || tracks.length != rawTracks.length) {
      // Persist the migration/prune so the next boot reads clean v2 data.
      await save(tracks);
    }
    return tracks;
  }

  /// Atomically writes the v2 manifest envelope.
  Future<void> _pendingSave = Future<void>.value();

  Future<void> save(List<Track> tracks) {
    final snapshot = List<Track>.of(tracks);
    final write = _pendingSave.then((_) => _saveSnapshot(snapshot));
    _pendingSave = write.catchError((Object _) {});
    return write;
  }

  Future<void> _saveSnapshot(List<Track> tracks) async {
    final manifest = await _manifestFile();
    await ensureDir(manifest.parent.path);

    final payload = <String, dynamic>{
      'schemaVersion': schemaVersion,
      'tracks': tracks.map((track) => track.toJson()).toList(),
      'savedAt': DateTime.now().toUtc().toIso8601String(),
    };
    final json = const JsonEncoder.withIndent('  ').convert(payload);

    final temp = File('${manifest.path}.tmp');
    await temp.writeAsString(json, flush: true);
    try {
      await temp.rename(manifest.path);
    } on FileSystemException {
      // Windows cannot rename onto an existing target; delete-then-rename
      // keeps the window where the manifest is absent as short as possible.
      if (await manifest.exists()) {
        await manifest.delete();
      }
      await temp.rename(manifest.path);
    }
  }

  /// Loads the manifest and merges in any audio files that exist on disk in
  /// the Music folder but are missing from it — this is what repopulates a
  /// library after a reinstall once downloads live in storage that outlives
  /// the app. Order: manifest entries first (as stored), then recovered
  /// orphans newest-first by file time. The merged list is persisted.
  Future<List<Track>> loadMergingDisk() async {
    final manifest = await load();
    final knownPaths = manifest.map((t) => canonical(t.filePath)).toSet();

    final musicDir = await musicDirectory();
    final orphans = <Track>[];
    if (await musicDir.exists()) {
      await for (final entity in musicDir.list(recursive: true)) {
        if (entity is! File) continue;
        if (!isAudioFile(entity.path)) continue;
        if (knownPaths.contains(canonical(entity.path))) continue;
        orphans.add(await _trackFromDiskFile(entity));
      }
    }

    if (orphans.isEmpty) return manifest;

    orphans.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    final merged = [...manifest, ...orphans];
    await save(merged);
    return merged;
  }

  /// Maps a stored path at the private root onto the audio root when the
  /// file exists there instead (audio migrated to public storage).
  Future<String> _relocatedPath(String path) async {
    if (await _audioFileExists(path)) return path;
    final root = await rootDirectory();
    final audioRoot = await audioRootDirectory();
    final rootPath = canonical(root.path);
    final audioPath = canonical(audioRoot.path);
    if (audioPath == rootPath) return path;
    final normalized = canonical(path);
    if (!normalized.startsWith('$rootPath/')) return path;
    final candidate = '$audioPath${normalized.substring(rootPath.length)}';
    return File(candidate).existsSync() ? candidate : path;
  }

  /// Looks for sidecar artwork next to an audio file
  /// (`<stem>.jpg|jpeg|png|webp`), then in the private `Art` folder keyed by
  /// the audio file's stem (artwork can't reliably sit beside public audio).
  Future<String?> findArtworkForAudio(String audioFilePath) async {
    final dot = audioFilePath.lastIndexOf('.');
    final stem = dot == -1 ? audioFilePath : audioFilePath.substring(0, dot);

    for (final extension in _artworkExtensions) {
      final candidate = File('$stem.$extension');
      if (await candidate.exists()) {
        return candidate.path;
      }
    }

    try {
      final artDir = await _artDirectory();
      final fileStem = _stem(audioFilePath);
      for (final extension in _artworkExtensions) {
        final candidate = File('${artDir.path}/$fileStem.$extension');
        if (await candidate.exists()) {
          return candidate.path;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Deletes every file under Music whose name stem matches [baseName]'s stem
  /// (audio plus any sidecar artwork / leftover `.part` files).
  Future<void> deleteArtifactsForBaseName(String baseName) async {
    final normalized = baseName.trim();
    if (normalized.isEmpty) return;

    final musicDir = await musicDirectory();
    if (!await musicDir.exists()) return;

    final stem = _stem(normalized);
    await for (final entity in musicDir.list(recursive: true)) {
      if (entity is! File) continue;
      if (_stem(entity.uri.pathSegments.last) != stem) continue;
      if (await entity.exists()) {
        if (isAudioFile(entity.path)) {
          await deleteAudioFile(entity.path);
        } else {
          try {
            await entity.delete();
          } on FileSystemException {
            // Sidecars that survive are harmless; leave them behind.
          }
        }
      }
    }
  }

  /// Deletes an audio file; on Android a file a previous install left in
  /// public Music needs the system consent dialog (MediaStore
  /// .createDeleteRequest), invoked via the native channel. Throws a precise
  /// error when the file survives.
  Future<void> deleteAudioFile(String path) async {
    final file = File(path);
    if (!await file.exists()) return;
    try {
      await file.delete();
    } on FileSystemException {
      // Fall through to the consent path below.
    }
    if (!await file.exists()) return;
    if (!Platform.isAndroid) {
      throw FileSystemException('Could not delete $path', path);
    }
    var granted = false;
    try {
      granted =
          await const MethodChannel(
            'monolith/media_import',
          ).invokeMethod<bool>('requestAudioDelete', {'path': path}) ??
          false;
    } on MissingPluginException {
      granted = false;
    } on PlatformException {
      granted = false;
    }
    if (!granted && await file.exists()) {
      throw FileSystemException(
        'Android requires your confirmation to delete songs an older '
        'install saved to public Music. Grant it in the system dialog, or '
        'remove the file in the Files app: $path',
        path,
      );
    }
  }

  /// Builds a best-effort [Track] for a file found on disk.
  ///
  /// The id derives from the path hash using the exact same formula as v1
  /// (`disk-<hash>`), so files recovered by v1 and re-recovered here never
  /// duplicate each other across the migration.
  Future<Track> _trackFromDiskFile(File file) async {
    final fileName = file.uri.pathSegments.last;
    DateTime addedAt;
    try {
      addedAt = (await file.stat()).modified;
    } catch (_) {
      addedAt = DateTime.fromMillisecondsSinceEpoch(0);
    }
    return Track(
      id: 'disk-${file.path.hashCode}',
      title: _stem(fileName),
      artist: 'Unknown',
      album: 'Downloads',
      genre: 'Downloaded audio',
      durationMs: 0,
      filePath: file.path,
      artworkPath: await findArtworkForAudio(file.path),
      source: TrackSource.downloaded,
      addedAt: addedAt,
    );
  }

  Future<File> _manifestFile() async {
    final root = await rootDirectory();
    return File('${root.path}/$_manifestFileName');
  }

  Future<bool> _audioFileExists(String path) async {
    if (path.trim().isEmpty) return false;
    try {
      return await File(path).exists();
    } catch (_) {
      return false;
    }
  }

  /// Creates [path] recursively if missing and returns its [Directory].
  static Future<Directory> ensureDir(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static bool isAudioFile(String path) =>
      audioExtensions.contains(_extension(path));

  /// Normalises separators so Windows/POSIX paths compare equal.
  static String canonical(String path) => path.replaceAll('\\', '/');

  static String _extension(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1 || dot == path.length - 1) return '';
    return path.substring(dot + 1).toLowerCase();
  }

  static String _stem(String name) {
    final separatorIndex = name.lastIndexOf(Platform.pathSeparator);
    final fileName = separatorIndex == -1
        ? name
        : name.substring(separatorIndex + 1);
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex <= 0) return fileName;
    return fileName.substring(0, dotIndex);
  }
}
