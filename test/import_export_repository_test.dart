import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monolith/data/platform_channels/media_import_channel.dart';
import 'package:monolith/data/repositories/import_export_repository.dart';
import 'package:monolith/data/services/storage/library_store.dart';
import 'package:monolith/domain/models/track.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testChannel = MethodChannel('monolith/media_import');
  late Directory fixtureRoot;
  late Directory scratchDir;

  void setChannelHandler(Future<Object?>? Function(MethodCall call)? handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(testChannel, handler);
  }

  setUp(() async {
    fixtureRoot = await Directory.systemTemp.createTemp('mono_p2_fixtures');
    scratchDir = await Directory.systemTemp.createTemp('mono_p2_scratch');
    setChannelHandler(null);
  });

  tearDown(() async {
    setChannelHandler(null);
    for (final dir in [fixtureRoot, scratchDir]) {
      try {
        if (await dir.exists()) await dir.delete(recursive: true);
      } on FileSystemException catch (_) {
        // Best-effort cleanup; a locked temp tree must not fail the suite.
      }
    }
  });

  LibraryStore storeFor(String name) => LibraryStore(
    rootDirFactory: () async => Directory('${fixtureRoot.path}/$name'),
  );

  ImportExportRepository repository({
    required LibraryStore store,
    AudioFilePicker? picker,
  }) {
    return ImportExportRepository(
      channel: MediaImportChannel(channel: testChannel),
      libraryStore: store,
      tempDirProvider: () => scratchDir,
      audioFilePicker: picker,
    );
  }

  group('importFromFiles', () {
    test(
      'copies picked audio into Music/Imports and registers tracks',
      () async {
        final sourceA = File('${fixtureRoot.path}/Song One.mp3')
          ..writeAsBytesSync(utf8.encode('aaa-bytes'));
        final sourceB = File('${fixtureRoot.path}/Song Two.flac')
          ..writeAsBytesSync(utf8.encode('bbb-bytes'));
        final store = storeFor('device-a');
        final repo = repository(
          store: store,
          picker: () async => [XFile(sourceA.path), XFile(sourceB.path)],
        );

        final tracks = await repo.importFromFiles();

        expect(tracks, hasLength(2));
        final importsDir = Directory(
          '${(await store.musicDirectory()).path}/Imports',
        );
        final copiedBytes = <String, String>{};
        for (final track in tracks) {
          expect(track.source, TrackSource.imported);
          expect(track.filePath, startsWith(importsDir.path));
          final copy = File(track.filePath);
          expect(await copy.exists(), isTrue, reason: track.filePath);
          copiedBytes[track.title] = await copy.readAsString();
        }
        // Bytes were copied verbatim from the picked files.
        expect(copiedBytes['Song One'], 'aaa-bytes');
        expect(copiedBytes['Song Two'], 'bbb-bytes');

        // The manifest persisted the imported copies.
        final persisted = await store.load();
        expect(
          persisted.map((t) => t.title),
          containsAll(['Song One', 'Song Two']),
        );
      },
    );

    test(
      'returns empty and writes nothing when the picker is dismissed',
      () async {
        final store = storeFor('device-empty');
        final repo = repository(store: store, picker: () async => []);

        final tracks = await repo.importFromFiles();

        expect(tracks, isEmpty);
        expect(await store.load(), isEmpty);
      },
    );
  });

  group('backup / restore round trip', () {
    test('zip then restore yields the same track count and metadata', () async {
      final storeA = storeFor('device-src');
      final musicA = await storeA.musicDirectory();
      File(
        '${musicA.path}/Alpha.mp3',
      ).writeAsBytesSync(utf8.encode('alpha-bytes'));
      File(
        '${musicA.path}/Beta.flac',
      ).writeAsBytesSync(utf8.encode('beta-bytes'));
      await storeA.save([
        Track(
          id: 't-alpha',
          title: 'Alpha',
          artist: 'Artist A',
          durationMs: 111000,
          filePath: '${musicA.path}/Alpha.mp3',
          addedAt: DateTime(2026, 1, 1),
        ),
        Track(
          id: 't-beta',
          title: 'Beta',
          artist: 'Artist B',
          durationMs: 222000,
          filePath: '${musicA.path}/Beta.flac',
          addedAt: DateTime(2026, 1, 2),
        ),
      ]);

      final zip = await repository(
        store: storeA,
      ).buildBackupArchive(await storeA.load());
      expect(await zip.exists(), isTrue);
      expect(await zip.length(), greaterThan(0));

      // Fresh-install simulation: brand-new root + store.
      final storeB = storeFor('device-fresh');
      final restored = await repository(store: storeB).restoreBackup(zip.path);

      expect(restored, hasLength(2));
      expect(restored.map((t) => t.title), containsAll(['Alpha', 'Beta']));

      final alpha = restored.singleWhere((t) => t.title == 'Alpha');
      expect(alpha.artist, 'Artist A');
      expect(alpha.durationMs, 111000);
      expect(alpha.source, TrackSource.imported);
      expect(await File(alpha.filePath).exists(), isTrue);
      expect(await File(alpha.filePath).readAsString(), 'alpha-bytes');

      // Restore persisted the merged manifest on the fresh install.
      final persisted = await storeB.load();
      expect(persisted, hasLength(2));
    });
  });

  group('importFromMusicApp (native picker statuses)', () {
    test(
      'keeps only copied items; protected/unavailable/failed are skipped',
      () async {
        final sandboxDir = Directory('${fixtureRoot.path}/sandbox')
          ..createSync(recursive: true);
        final localCopy = File('${sandboxDir.path}/Local Song.m4a')
          ..writeAsBytesSync(utf8.encode('local-bytes'));

        setChannelHandler((call) async {
          if (call.method != 'pickFromMusicLibrary') return null;
          return [
            {
              'status': 'copied',
              'path': localCopy.path,
              'title': 'Local Song',
              'artist': 'Local Artist',
              'durationMs': 123000,
            },
            {
              'status': 'protected',
              'title': 'DRM Song',
              'artist': 'Apple',
              'reason': 'DRM',
            },
            {'status': 'unavailable', 'title': 'Cloud Song', 'artist': 'Apple'},
            {
              'status': 'failed',
              'title': 'Broken',
              'artist': 'X',
              'reason': 'io error',
            },
          ];
        });

        final store = storeFor('device-c');
        final tracks = await repository(store: store).importFromMusicApp();

        expect(tracks, hasLength(1));
        expect(tracks.single.title, 'Local Song');
        expect(tracks.single.artist, 'Local Artist');
        expect(tracks.single.durationMs, 123000);
        expect(tracks.single.source, TrackSource.imported);
        expect(await File(tracks.single.filePath).exists(), isTrue);
      },
    );
  });

  group('DTO mapping', () {
    test(
      'ImportedItemResult maps native status strings including unknown ones',
      () {
        expect(
          ImportedItemResult.fromMap({'status': 'copied'}).status,
          ImportedItemStatus.copied,
        );
        expect(
          ImportedItemResult.fromMap({'status': 'protected'}).status,
          ImportedItemStatus.protected,
        );
        expect(
          ImportedItemResult.fromMap({'status': 'unavailable'}).status,
          ImportedItemStatus.unavailable,
        );
        expect(
          ImportedItemResult.fromMap({'status': 'failed'}).status,
          ImportedItemStatus.failed,
        );
        // Unknown future status values degrade to failed instead of crashing.
        expect(
          ImportedItemResult.fromMap({'status': 'mystery'}).status,
          ImportedItemStatus.failed,
        );

        final full = ImportedItemResult.fromMap({
          'status': 'copied',
          'path': '/x.mp3',
          'title': 'T',
          'artist': 'A',
          'reason': null,
          'durationMs': 5,
        });
        expect(full.path, '/x.mp3');
        expect(full.title, 'T');
        expect(full.artist, 'A');
        expect(full.reason, isNull);
        expect(full.durationMs, 5);
      },
    );

    test('ExportResult parses savedCount/canceled tolerantly', () {
      final result = ExportResult.fromMap({'savedCount': 2, 'canceled': false});
      expect(result.savedCount, 2);
      expect(result.canceled, isFalse);

      final fallback = ExportResult.fromMap(null);
      expect(fallback.savedCount, 0);
      expect(fallback.canceled, isFalse);
    });

    test('exportToSaf parses the native reply through the channel', () async {
      setChannelHandler((call) async {
        if (call.method != 'exportToSaf') return null;
        return {'savedCount': 2, 'canceled': false};
      });

      final result = await MediaImportChannel(
        channel: testChannel,
      ).exportToSaf(['/a.mp3', '/b.flac'], ['audio/mpeg', 'audio/flac']);

      expect(result.savedCount, 2);
      expect(result.canceled, isFalse);
    });
  });
}
