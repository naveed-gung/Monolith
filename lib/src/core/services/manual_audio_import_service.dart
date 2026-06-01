import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

class ImportedAudioFile {
  const ImportedAudioFile({required this.name, this.path, this.bytes});

  final String name;
  final String? path;
  final Uint8List? bytes;

  bool get hasReadableContent =>
      (path != null && path!.trim().isNotEmpty) || bytes != null;
}

class ManualAudioImportService {
  Future<List<ImportedAudioFile>> pickAudioFiles() async {
    const audioTypeGroup = XTypeGroup(
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

    final pickedFiles = await openFiles(
      acceptedTypeGroups: const [audioTypeGroup],
      confirmButtonText: 'Import',
    );

    final imports = <ImportedAudioFile>[];
    for (final file in pickedFiles) {
      final resolvedPath = file.path.trim().isEmpty ? null : file.path;
      imports.add(
        ImportedAudioFile(
          name: file.name,
          path: resolvedPath,
          bytes: resolvedPath == null ? await file.readAsBytes() : null,
        ),
      );
    }

    return imports;
  }
}
