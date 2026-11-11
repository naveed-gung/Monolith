import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

import '../models/music_models.dart';
import 'audio_formats.dart';

class DownloadStore {
  /// Test seam: [android] fakes `Platform.isAndroid` and [publicMusicDir]
  /// replaces the native `getPublicMusicDir` channel answer so the public-
  /// storage layout and migration can be exercised with temp dirs.
  DownloadStore({bool? android, String? publicMusicDir})
    : _isAndroid = android ?? Platform.isAndroid,
      _publicMusicDirOverride = publicMusicDir;

  final bool _isAndroid;
  final String? _publicMusicDirOverride;

  Future<Map<Object?, Object?>> readAudioMetadata(String path) async {
    try {
      return await const MethodChannel('monolith/media_import')
              .invokeMapMethod<Object?, Object?>('readAudioMetadata', {
                'path': path,
              })
              .timeout(const Duration(seconds: 10)) ??
          {};
    } catch (_) {
      return {};
    }
  }

  Future<Track> resolveMetadata(Track track) async {
    if (track.filePath == null || track.duration > Duration.zero) return track;
    final metadata = await readAudioMetadata(track.filePath!);
    final durationMs = (metadata['durationMs'] as num?)?.toInt() ?? 0;
    return durationMs > 0
        ? track.copyWith(duration: Duration(milliseconds: durationMs))
        : track;
  }

  static const _sep = '/';
  Future<void> _pendingWrite = Future<void>.value();

  /// Audio container extensions we recognise when rebuilding the library from
  /// files found on disk (used by [loadTracksMergingDisk]).
  static const _audioExtensions = supportedAudioExtensions;

  /// Monolith's own private top-level folder — manifest and artwork sidecars
  /// live here. On iOS this lives in the app's Documents directory, which —
  /// with UIFileSharingEnabled + LSSupportsOpeningDocumentsInPlace set in
  /// Info.plist — shows up in the Files app under "On My iPhone › Monolith".
  /// On Android it lives in the app's external files directory so the system
  /// Files app can browse it without extra permissions. The private root is
  /// wiped on uninstall; audio therefore lives under [_audioRootDirectory].
  Future<Directory> _rootDirectory() async {
    if (_isAndroid) {
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        return _ensureDir('${extDir.path}${_sep}Monolith');
      }
    }
    final documentsDirectory = await getApplicationDocumentsDirectory();
    return _ensureDir('${documentsDirectory.path}${_sep}Monolith');
  }

  Future<Directory?>? _publicAudioRoot;

  /// The audio storage root. On Android this is the public `Music/Monolith`
  /// folder (same location `writeToPublicMusic` uses) so songs survive an
  /// uninstall. Falls back to the private root when the public folder can't
  /// be resolved or created — never throws, never loses data.
  Future<Directory> _audioRootDirectory() {
    if (!_isAndroid) return _rootDirectory();
    return (_publicAudioRoot ??= _resolvePublicAudioRoot()).then(
      (dir) async => dir ?? await _rootDirectory(),
    );
  }

  Future<Directory?> _resolvePublicAudioRoot() async {
    if (_publicMusicDirOverride != null) {
      return _ensureDir(_publicMusicDirOverride);
    }
    try {
      final path = await const MethodChannel(
        'monolith/media_import',
      ).invokeMethod<String>('getPublicMusicDir');
      if (path == null || path.isEmpty) return null;
      return await _ensureDir(path);
    } catch (_) {
      return null;
    }
  }

  /// `true` when audio is stored in the public Music folder (Android) and
  /// therefore outlives uninstalls.
  Future<bool> audioStorageIsPublic() async {
    if (!_isAndroid) return false;
    final dir = await (_publicAudioRoot ??= _resolvePublicAudioRoot());
    return dir != null;
  }

  /// The "Music" subfolder where downloaded tracks land. This is the folder the
  /// user sees as their library on disk.
  Future<Directory> getDownloadDirectory() async {
    final root = await _audioRootDirectory();
    return _ensureDir('${root.path}${_sep}Music');
  }

  /// Artwork sidecars for public audio live in the private `Art` folder:
  /// scoped storage (API 30+) only allows media files matching a public
  /// directory's type, so images next to audio in Music/ are unreliable.
  /// Lookup falls back to sidecars sitting beside the audio file.
  /// Private directory holding artwork sidecars; exposed so download
  /// pipelines can place non-audio files outside the public Music folder.
  Future<Directory> artworkDirectory() => _artDirectory();

  Future<Directory> _artDirectory() async {
    final root = await _rootDirectory();
    return _ensureDir('${root.path}${_sep}Art');
  }

  Future<Directory> _ensureDir(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Resolves a stored path against every root that can hold Monolith files:
  /// the private root (manifest, artwork, pre-1.5.1 audio) and the public
  /// audio root (post-1.5.1 audio that survives uninstalls).
  Future<String?> _resolveUnderRoots(String saved) async {
    if (File(saved).existsSync()) return saved;
    final normalized = saved.replaceAll('\\', '/');
    final roots = <Directory>[
      await _audioRootDirectory(),
      await _rootDirectory(),
    ];
    for (final root in roots) {
      final marker = normalized.lastIndexOf('/Monolith/');
      if (marker >= 0) {
        final relative = normalized.substring(marker + '/Monolith/'.length);
        if (!relative.split('/').any((part) => part == '..')) {
          final candidate = '${root.path}/$relative';
          if (File(candidate).existsSync()) return candidate;
        }
      }
      final filename = normalized.split('/').last;
      if (filename.isNotEmpty) {
        final inMusic = '${root.path}/Music/$filename';
        if (File(inMusic).existsSync()) return inMusic;
        final inImports = '${root.path}/Music/Imports/$filename';
        if (File(inImports).existsSync()) return inImports;
      }
    }
    return saved;
  }

  Future<String?> resolveTrackPath(String? saved) async {
    if (saved == null) return null;
    return _resolveUnderRoots(saved);
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

    List<dynamic> decoded;
    try {
      final json = jsonDecode(rawContent);
      final entries = json is List
          ? json
          : (json is Map ? json['tracks'] : null);
      if (entries is! List) {
        throw const FormatException('Invalid track manifest');
      }
      decoded = entries;
    } on FormatException {
      await manifest.copy(
        '${manifest.path}.corrupt-${DateTime.now().microsecondsSinceEpoch}',
      );
      return const []; // Disk recovery still runs; original metadata is retained.
    }

    Future<String?> recoverAsync(String? saved) async {
      if (saved == null) return null;
      return _resolveUnderRoots(saved);
    }

    var damagedEntry = false;
    final resolved = <Track?>[];
    for (final item in decoded) {
      try {
        final track = Track.fromJson(item as Map<String, dynamic>);
        resolved.add(
          track.copyWith(
            source:
                (track.filePath?.replaceAll('\\', '/').contains('/Imports/') ??
                    false)
                ? TrackSource.imported
                : track.source,
            filePath: await recoverAsync(track.filePath),
            artworkFilePath: await recoverAsync(track.artworkFilePath),
          ),
        );
      } on TypeError {
        damagedEntry = true;
        resolved.add(null);
      } on ArgumentError {
        damagedEntry = true;
        resolved.add(null);
      }
    }
    final tracks = resolved.whereType<Track>()
        .where((track) {
          if (track.filePath == null) return false;
          final file = File(track.filePath!);
          if (!file.existsSync()) return false;
          try {
            if (file.lengthSync() == 0) return false;
          } catch (_) {
            return false;
          }
          return true;
        })
        .toList();
    // Missing files may be temporarily inaccessible; never prune the manifest
    // during a read. The next explicit library write persists recovered paths.

    if (damagedEntry) {
      await manifest.copy(
        '${manifest.path}.corrupt-${DateTime.now().microsecondsSinceEpoch}',
      );
    }
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
  /// One-time idempotent move of pre-1.5.1 audio out of the private
  /// `Android/data` folder into public `Music/Monolith` so it survives
  /// uninstalls. Copies (verifying sizes), rewrites manifest paths, then
  /// removes each source; a marker file records completion so later loads
  /// are cheap. On any per-file failure the original is kept. Artwork
  /// sidecars move to the private Art folder instead.
  Future<void> migrateToPublicStorage() async {
    if (!_isAndroid) return;
    final public = await (_publicAudioRoot ??= _resolvePublicAudioRoot());
    if (public == null) return;
    final privateRoot = await _rootDirectory();
    final privatePath = _canonical(privateRoot.path);
    if (_canonical(public.path) == privatePath) return;
    final marker = File('$privatePath${_sep}migrated-to-public');
    if (await marker.exists()) return;

    final legacyMusic = Directory('$privatePath${_sep}Music');
    var clean = true;
    if (await legacyMusic.exists()) {
      await for (final entity in legacyMusic.list(recursive: true)) {
        if (entity is! File) continue;
        final ext = _extension(entity.path);
        final relative = _canonical(
          entity.path,
        ).substring('$privatePath/Music'.length);
        if (_audioExtensions.contains(ext)) {
          final target = File('${public.path}${_sep}Music$relative');
          try {
            await target.parent.create(recursive: true);
            if (!await target.exists()) {
              await entity.copy(target.path);
            }
            if (await target.length() != await entity.length()) {
              clean = false;
              continue;
            }
            await entity.delete();
          } catch (_) {
            clean = false;
          }
        } else if (['jpg', 'jpeg', 'png', 'webp'].contains(ext)) {
          try {
            final art = await _artDirectory();
            final artTarget = File(
              '${art.path}$_sep${_stem(entity.path)}.$ext',
            );
            if (!await artTarget.exists()) {
              await entity.copy(artTarget.path);
            }
            await entity.delete();
          } catch (_) {
            // Artwork move is best-effort; a stray sidecar is harmless.
          }
        }
      }
    }

    // loadTracks already repoints file paths under the public root; moved
    // artwork sidecars need the same treatment — anything stale is re-found
    // by stem (Art folder) or cleared.
    final manifest = await loadTracks();
    final rewritten = <Track>[];
    var changed = false;
    for (final track in manifest) {
      final artExists =
          track.artworkFilePath != null &&
          File(track.artworkFilePath!).existsSync();
      final art = artExists
          ? track.artworkFilePath
          : await findArtworkForAudio(track.filePath ?? '');
      if (art != track.artworkFilePath) {
        changed = true;
        rewritten.add(track.copyWith(artworkFilePath: art));
      } else {
        rewritten.add(track);
      }
    }
    if (changed) await saveTracks(rewritten);

    if (clean) {
      await marker.writeAsString('done', flush: true);
    }
  }

  Future<List<Track>> loadTracksMergingDisk() async {
    await migrateToPublicStorage();
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
        try {
          if (await entity.length() == 0) continue;
        } catch (_) {
          continue;
        }
        orphans.add(await _trackFromDiskFile(entity));
      }
    }

    orphans.sort(
      (a, b) => (b.addedAt ?? DateTime(0)).compareTo(a.addedAt ?? DateTime(0)),
    );
    final merged = <Track>[];
    for (final track in [...manifest, ...orphans]) {
      merged.add(await resolveMetadata(track));
    }
    // Persist so the re-discovered files become first-class manifest entries
    // (smart-playlist counts, ordering, etc.) on the next boot.
    if (orphans.isNotEmpty ||
        merged.asMap().entries.any(
          (e) => e.value.duration != manifest[e.key].duration,
        )) {
      await saveTracks(merged);
    }
    return merged;
  }

  Future<Track> _trackFromDiskFile(File file) async {
    final name = file.uri.pathSegments.last;
    final title = _stem(name).replaceFirst(
      RegExp(
        r'-(?:[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}|shared-[0-9a-f]{16})$',
      ),
      '',
    );
    final imported = _canonical(file.path).contains('/Imports/');
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
      album: imported ? 'Imported audio' : 'Downloads',
      genre: imported ? 'Imported audio' : 'Downloaded audio',
      duration: Duration.zero,
      colors: Track.paletteForSeed(file.path),
      blurb: 'Recovered from $name',
      source: imported ? TrackSource.imported : TrackSource.downloaded,
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

    // Public audio keeps artwork in the private Art folder keyed by stem.
    // Wrapped: artwork lookup must never fail a caller that only needs audio.
    try {
      final artDir = await _artDirectory();
      final fileStem = _stem(audioFilePath);
      for (final extension in ['jpg', 'jpeg', 'png', 'webp']) {
        final artworkFile = File('${artDir.path}$_sep$fileStem.$extension');
        if (await artworkFile.exists()) {
          return artworkFile.path;
        }
      }
    } catch (_) {
      // No Art dir (storage unavailable) — treat as no artwork.
    }

    return null;
  }

  /// Moves an artwork sidecar sitting beside a public audio file into the
  /// private Art folder, since scoped storage can refuse images in Music/.
  /// No-op when the audio lives under the private root already.
  Future<void> moveArtworkBeside(String audioFilePath) async {
    try {
      final root = await _rootDirectory();
      if (_canonical(audioFilePath).startsWith('${_canonical(root.path)}/')) {
        return;
      }
      final extensionIndex = audioFilePath.lastIndexOf('.');
      final stem = extensionIndex == -1
          ? audioFilePath
          : audioFilePath.substring(0, extensionIndex);
      final artDir = await _artDirectory();
      for (final extension in ['jpg', 'jpeg', 'png', 'webp']) {
        final sidecar = File('$stem.$extension');
        if (await sidecar.exists()) {
          final target = File('${artDir.path}$_sep${_stem(audioFilePath)}.$extension');
          await sidecar.copy(target.path);
          await sidecar.delete();
        }
      }
    } catch (_) {
      // Best-effort: losing artwork must never fail a download.
    }
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
        if (_audioExtensions.contains(_extension(entity.path))) {
          await _deleteAudioFile(entity);
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

  /// Deletes [file]; on Android a file a previous install created in public
  /// Music can't be removed directly — the system consent dialog
  /// (MediaStore.createDeleteRequest) is shown via the native channel.
  /// Throws a precise error when the file still exists afterwards.
  Future<void> _deleteAudioFile(File file) async {
    if (!await file.exists()) return;
    try {
      await file.delete();
    } on FileSystemException {
      // Fall through to the consent path below.
    }
    if (!await file.exists()) return;
    if (!_isAndroid) {
      throw FileSystemException(
        'Could not delete ${file.path}',
        file.path,
      );
    }
    var granted = false;
    try {
      granted =
          await const MethodChannel(
            'monolith/media_import',
          ).invokeMethod<bool>('requestAudioDelete', {'path': file.path}) ??
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
        'remove the file in the Files app: ${file.path}',
        file.path,
      );
    }
  }

  Future<void> _deleteWithArtwork(String audioFilePath) async {
    await _deleteAudioFile(File(audioFilePath));

    final extensionIndex = audioFilePath.lastIndexOf('.');
    final stem = extensionIndex == -1
        ? audioFilePath
        : audioFilePath.substring(0, extensionIndex);

    for (final extension in ['jpg', 'jpeg', 'png', 'webp', 'part']) {
      final artifact = File('$stem.$extension');
      if (await artifact.exists()) {
        try {
          await artifact.delete();
        } on FileSystemException {
          // Non-audio sidecars can't use the consent path; leave them.
        }
      }
    }

    // Art-dir sidecars live under the private root and always delete cleanly.
    try {
      final artDir = await _artDirectory();
      final fileStem = _stem(audioFilePath);
      for (final extension in ['jpg', 'jpeg', 'png', 'webp']) {
        final artifact = File('${artDir.path}$_sep$fileStem.$extension');
        if (await artifact.exists()) {
          await artifact.delete();
        }
      }
    } catch (_) {
      // No Art dir or a read-only file — harmless leftovers.
    }
  }

  String _stem(String name) {
    final separatorIndex = _canonical(name).lastIndexOf('/');
    final fileName = separatorIndex == -1
        ? _canonical(name)
        : _canonical(name).substring(separatorIndex + 1);
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex <= 0) {
      return fileName;
    }
    return fileName.substring(0, dotIndex);
  }
}
