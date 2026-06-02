import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../models/music_models.dart';

class DownloadStore {
  Future<Directory> getDownloadDirectory() async {
    // On Android, use the app's external files directory so the folder is
    // visible in the system Files app (Files by Google, Samsung My Files, etc.)
    // without needing special permissions. Falls back to internal docs on iOS.
    if (Platform.isAndroid) {
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        final dir = Directory(
          '${extDir.path}${Platform.pathSeparator}downloads',
        );
        if (!await dir.exists()) await dir.create(recursive: true);
        return dir;
      }
    }
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final downloadDirectory = Directory(
      '${documentsDirectory.path}${Platform.pathSeparator}downloads',
    );

    if (!await downloadDirectory.exists()) {
      await downloadDirectory.create(recursive: true);
    }

    return downloadDirectory;
  }

  Future<List<Track>> loadTracks() async {
    final manifest = await _manifestFile();
    if (!await manifest.exists()) {
      return const [];
    }

    final rawContent = await manifest.readAsString();
    if (rawContent.trim().isEmpty) {
      return const [];
    }

    final decoded = jsonDecode(rawContent) as List<dynamic>;
    final tracks = decoded
        .map((item) => Track.fromJson(item as Map<String, dynamic>))
        .where(
          (track) =>
              track.filePath != null && File(track.filePath!).existsSync(),
        )
        .toList();

    if (tracks.length != decoded.length) {
      await saveTracks(tracks);
    }

    return tracks;
  }

  Future<void> saveTracks(List<Track> tracks) async {
    final manifest = await _manifestFile();
    final payload = tracks.map((track) => track.toJson()).toList();
    await manifest.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
    );
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

  Future<File> _manifestFile() async {
    final downloadDirectory = await getDownloadDirectory();
    return File(
      '${downloadDirectory.path}${Platform.pathSeparator}manifest.json',
    );
  }

  Future<Directory> _importDirectory() async {
    final downloadDirectory = await getDownloadDirectory();
    final importDirectory = Directory(
      '${downloadDirectory.path}${Platform.pathSeparator}imports',
    );

    if (!await importDirectory.exists()) {
      await importDirectory.create(recursive: true);
    }

    return importDirectory;
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
