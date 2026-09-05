import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../models/music_models.dart';

class DownloadStore {
  static const _sep = '/';
  Future<void> _pendingWrite = Future<void>.value();

  /// Audio container extensions we recognise when rebuilding the library from
  /// files found on disk (used by [loadTracksMergingDisk]).
  static const _audioExtensions = {
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

  /// Monolith's own top-level folder. On iOS this lives in the app's Documents
  /// directory, which — with UIFileSharingEnabled + LSSupportsOpeningDocuments
  /// InPlace set in Info.plist — shows up in the Files app under
  /// "On My iPhone › Monolith". On Android it lives in the app's external files
  /// directory so the system Files app can browse it without extra permissions.
  Future<Directory> _rootDirectory() async {
    if (Platform.isAndroid) {
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        return _ensureDir('${extDir.path}${_sep}Monolith');
      }
    }
    final documentsDirectory = await getApplicationDocumentsDirectory();
    return _ensureDir('${documentsDirectory.path}${_sep}Monolith');
  }

  /// The "Music" subfolder where downloaded tracks land. This is the folder the
  /// user sees as their library on disk.
  Future<Directory> getDownloadDirectory() async {
    final root = await _rootDirectory();
    return _ensureDir('${root.path}${_sep}Music');
  }

  Future<Directory> _ensureDir(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<List<Track>> loadTracks() async {
    await _pendingWrite;
    final manifest = await _manifestFile();
    if (!await manifest.exists()) {
      return const [];
    }

    final rawContent = await manifest.readAsString();
    if (rawContent.trim().isEmpty) {
      return const [];
    }

    final decoded = jsonDecode(rawContent) as List<dynamic>;
    final root = await _rootDirectory();
    String? recover(String? saved) {
      if (saved == null) return null;
      if (File(saved).existsSync()) return saved;
      final normalized = saved.replaceAll('\\', '/');
      final marker = normalized.lastIndexOf('/Monolith/');
      if (marker < 0) return saved;
      final relative = normalized.substring(marker + '/Monolith/'.length);
      if (relative.split('/').any((part) => part == '..')) return saved;
      final candidate = '${root.path}/$relative';
      return File(candidate).existsSync() ? candidate : saved;
    }

    final tracks = decoded
        .map((item) {
          final track = Track.fromJson(item as Map<String, dynamic>);
          return track.copyWith(
            filePath: recover(track.filePath),
            artworkFilePath: recover(track.artworkFilePath),
          );
        })
        .where(
          (track) =>
              track.filePath != null && File(track.filePath!).existsSync(),
        )
        .toList();
    // Missing files may be temporarily inaccessible; never prune the manifest
    // during a read. The next explicit library write persists recovered paths.

    return tracks;
  }

  /// Load the manifest, then merge in any audio files that exist on disk in the
  /// Music folder but are missing from the manifest, re-adding them with
  /// best-effort metadata (filename → title, file mtime → addedAt).
  ///
  /// This is what makes a library repopulate from surviving files: after a
  /// reinstall (or once downloads live in OS-public storage that outlives the
  /// app), the manifest may be gone while the audio files remain — this rebuilds
  /// the library from the files on disk. Order: manifest entries first
  /// (newest-first, as stored), then disk-only orphans by modified time
  /// (newest-first).
  Future<List<Track>> loadTracksMergingDisk() async {
    final manifest = await loadTracks();
    final known = manifest
        .map((t) => t.filePath)
        .whereType<String>()
        .map(_canonical)
        .toSet();

    final musicDir = await getDownloadDirectory();
    final orphans = <Track>[];
    if (await musicDir.exists()) {
      await for (final entity in musicDir.list(recursive: true)) {
        if (entity is! File) continue;
        final ext = _extension(entity.path);
        if (!_audioExtensions.contains(ext)) continue;
        if (known.contains(_canonical(entity.path))) continue;
        orphans.add(await _trackFromDiskFile(entity));
      }
    }

    if (orphans.isEmpty) return manifest;

    orphans.sort(
      (a, b) => (b.addedAt ?? DateTime(0)).compareTo(a.addedAt ?? DateTime(0)),
    );
    final merged = [...manifest, ...orphans];
    // Persist so the re-discovered files become first-class manifest entries
    // (smart-playlist counts, ordering, etc.) on the next boot.
    await saveTracks(merged);
    return merged;
  }

  Future<Track> _trackFromDiskFile(File file) async {
    final name = file.uri.pathSegments.last;
    final title = _stem(name);
    DateTime? addedAt;
    try {
      addedAt = (await file.stat()).modified;
    } catch (_) {
      addedAt = null;
    }
    final artwork = await findArtworkForAudio(file.path);
    return Track(
      // Stable id derived from the path so repeated rescans don't duplicate.
      id: 'disk-${file.path.hashCode}',
      title: title,
      artist: 'Unknown',
      album: 'Downloads',
      genre: 'Downloaded audio',
      duration: Duration.zero,
      colors: Track.paletteForSeed(file.path),
      blurb: 'Recovered from $name',
      source: TrackSource.downloaded,
      filePath: file.path,
      artworkFilePath: artwork,
      addedAt: addedAt,
    );
  }

  String _canonical(String path) => path.replaceAll('\\', '/');

  String _extension(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1 || dot == path.length - 1) return '';
    return path.substring(dot + 1).toLowerCase();
  }

  Future<void> saveTracks(List<Track> tracks) {
    final payload = const JsonEncoder.withIndent(
      '  ',
    ).convert(tracks.map((track) => track.toJson()).toList());
    final write = _pendingWrite.then((_) async {
      final manifest = await _manifestFile();
      final temporary = File('${manifest.path}.tmp');
      await temporary.writeAsString(payload, flush: true);
      await temporary.rename(manifest.path);
    });
    // Keep later writes usable after an error, while reporting this failure.
    _pendingWrite = write.catchError((Object _) {});
    return write;
  }

  Future<File> saveImportedAudio({
    required String preferredFileName,
    String? sourcePath,
    Uint8List? bytes,
  }) async {
    final hasSourcePath = sourcePath != null && sourcePath.trim().isNotEmpty;
    if (!hasSourcePath && bytes == null) {
      throw StateError(
        'Select an audio file that can be copied into Monolith.',
      );
    }

    final importDirectory = await _importDirectory();
    final destination = await _nextAvailableFile(
      importDirectory,
      preferredFileName,
    );

    if (hasSourcePath) {
      return File(sourcePath).copy(destination.path);
    }

    await destination.writeAsBytes(bytes!, flush: true);
    return destination;
  }

  Future<String?> findArtworkForAudio(String audioFilePath) async {
    final extensionIndex = audioFilePath.lastIndexOf('.');
    final stem = extensionIndex == -1
        ? audioFilePath
        : audioFilePath.substring(0, extensionIndex);

    for (final extension in ['jpg', 'jpeg', 'png', 'webp']) {
      final artworkFile = File('$stem.$extension');
      if (await artworkFile.exists()) {
        return artworkFile.path;
      }
    }

    return null;
  }

  Future<bool> hasValidAudioFile(String audioFilePath) async {
    final file = File(audioFilePath);
    if (!await file.exists()) {
      return false;
    }

    return await file.length() > 0;
  }

  Future<void> deleteArtifactsForTrack(Track track) async {
    final filePath = track.filePath;
    if (filePath == null || filePath.trim().isEmpty) {
      return;
    }

    await _deleteWithArtwork(filePath);
  }

  Future<void> deleteArtifactsForBaseName(String baseName) async {
    final normalized = baseName.trim();
    if (normalized.isEmpty) {
      return;
    }

    final downloadDirectory = await getDownloadDirectory();
    if (!await downloadDirectory.exists()) {
      return;
    }

    final stem = _stem(normalized);
    await for (final entity in downloadDirectory.list(recursive: true)) {
      if (entity is! File) {
        continue;
      }

      final entityStem = _stem(entity.uri.pathSegments.last);
      if (entityStem != stem) {
        continue;
      }

      if (await entity.exists()) {
        await entity.delete();
      }
    }
  }

  // Manifest lives at the Monolith root (not inside Music) so it persists
  // regardless of how the music subfolders are organised.
  Future<File> _manifestFile() async {
    final root = await _rootDirectory();
    return File('${root.path}${_sep}manifest.json');
  }

  // Imported audio goes into a dedicated subfolder of Music.
  Future<Directory> _importDirectory() async {
    final downloadDirectory = await getDownloadDirectory();
    return _ensureDir('${downloadDirectory.path}${_sep}Imports');
  }

  Future<File> _nextAvailableFile(
    Directory directory,
    String preferredFileName,
  ) async {
    final dotIndex = preferredFileName.lastIndexOf('.');
    final hasExtension =
        dotIndex > 0 && dotIndex < preferredFileName.length - 1;
    final nameStem = hasExtension
        ? preferredFileName.substring(0, dotIndex)
        : preferredFileName;
    final extension = hasExtension ? preferredFileName.substring(dotIndex) : '';

    var attempt = 0;
    while (true) {
      final suffix = attempt == 0 ? '' : '-${attempt + 1}';
      final candidate = File(
        '${directory.path}${Platform.pathSeparator}$nameStem$suffix$extension',
      );
      if (!await candidate.exists()) {
        return candidate;
      }
      attempt += 1;
    }
  }

  Future<void> _deleteWithArtwork(String audioFilePath) async {
    final file = File(audioFilePath);
    if (await file.exists()) {
      await file.delete();
    }

    final extensionIndex = audioFilePath.lastIndexOf('.');
    final stem = extensionIndex == -1
        ? audioFilePath
        : audioFilePath.substring(0, extensionIndex);

    for (final extension in ['jpg', 'jpeg', 'png', 'webp', 'part']) {
      final artifact = File('$stem.$extension');
      if (await artifact.exists()) {
        await artifact.delete();
      }
    }
  }

  String _stem(String name) {
    final separatorIndex = name.lastIndexOf(Platform.pathSeparator);
    final fileName = separatorIndex == -1
        ? name
        : name.substring(separatorIndex + 1);
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex <= 0) {
      return fileName;
    }
    return fileName.substring(0, dotIndex);
  }
}
