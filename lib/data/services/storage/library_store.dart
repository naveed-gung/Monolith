import 'dart:convert';
import 'dart:io';

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
  LibraryStore({RootDirFactory? rootDirFactory})
    : _rootDirFactory = rootDirFactory ?? defaultRootDirectory;

  final RootDirFactory _rootDirFactory;

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

  /// Monolith's own top-level data folder.
  Future<Directory> rootDirectory() => _rootDirFactory();

  /// The `Music` subfolder where audio lives; created on demand.
  Future<Directory> musicDirectory() async {
    final root = await rootDirectory();
    return ensureDir('${root.path}/$_musicFolderName');
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
      final track = Track.fromJson(item);
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

  /// Looks for sidecar artwork next to an audio file (`<stem>.jpg|jpeg|png|webp`).
  Future<String?> findArtworkForAudio(String audioFilePath) async {
    final dot = audioFilePath.lastIndexOf('.');
    final stem = dot == -1 ? audioFilePath : audioFilePath.substring(0, dot);

    for (final extension in _artworkExtensions) {
      final candidate = File('$stem.$extension');
      if (await candidate.exists()) {
        return candidate.path;
      }
    }
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
        await entity.delete();
      }
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
