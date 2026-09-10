import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'audio_formats.dart';

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
      extensions: supportedAudioExtensions,
      mimeTypes: ['audio/*'],
      uniformTypeIdentifiers: ['public.audio', 'public.mpeg-4'],
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
