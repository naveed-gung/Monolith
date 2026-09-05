import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:monolith/data/services/downloads/download_manager.dart';
import 'package:monolith/data/services/downloads/source_provider.dart';
import 'package:monolith/data/services/storage/library_store.dart';
import 'package:monolith/domain/models/download_task.dart';
import 'package:monolith/domain/models/track.dart';

/// Controllable connectivity probe — no platform channels involved.
class FakeProbe implements ConnectivityProbe {
  FakeProbe({this.unmetered = true});

  bool unmetered;
  final _changes = StreamController<void>.broadcast();

  @override
  Future<bool> isUnmetered() async => unmetered;

  @override
  Stream<void> get changes => _changes.stream;

  void setUnmetered(bool value) {
    unmetered = value;
    _changes.add(null);
  }

  void dispose() => _changes.close();
}

/// Scriptable provider whose downloads write real files into a destination
/// directory (mirroring the production wiring where that directory is the
/// library's Music folder).
class FakeSourceProvider implements SourceProvider {
  FakeSourceProvider(this.id);

  @override
  final String id;

  int inspectCalls = 0;
  final List<DownloadRequest> requests = [];
  Directory? destination;
  bool failInspect = false;
  bool failDownload = false;

  @override
  Future<DownloadPreview> inspect(Uri source) async {
    inspectCalls++;
    if (failInspect ||
        (id == 'good' && source.queryParameters['v'] == 'nope')) {
      throw StateError('cannot handle $source');
    }
    return DownloadPreview(
      title:
          'Song ${source.queryParameters['v'] ?? (source.pathSegments.isEmpty ? source.toString() : source.pathSegments.last)}',
      artist: 'Fake Artist',
      durationMs: 42000,
      artworkUrl: 'https://example.com/art.jpg',
      suggestedFileName: 'song',
    );
  }

  @override
  Stream<DownloadEvent> download(DownloadRequest req) async* {
    requests.add(req);
    if (failDownload) {
      yield const DownloadFailed(message: 'boom');
      return;
    }
    final dir = destination!;
    await dir.create(recursive: true);
    final stem = _stemOf(req.fileName);
    final audio = File('${dir.path}/$stem.m4a');
    if (await audio.exists()) await audio.delete();

    var received = 0;
    for (var i = 0; i < 3; i++) {
      await audio.writeAsBytes(const [1, 2, 3, 4], mode: FileMode.append);
      received += 4;
      yield DownloadProgress(received: received, total: 12);
    }
    // Sidecar artwork, like the real provider.
    await File('${dir.path}/$stem.jpg').writeAsBytes(const [9, 9]);
    yield DownloadCompleted(filePath: audio.path);
  }

  static String _stemOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    return dot <= 0 ? fileName : fileName.substring(0, dot);
  }
}

/// Provider whose byte stream is driven manually by the test — used to hold
/// transfers open for pause/cancel assertions. Mirrors the real provider's
/// `async*` + finally-cleanup structure.
class ManualSourceProvider implements SourceProvider {
  var _controller = StreamController<DownloadEvent>();
  final List<DownloadRequest> requests = [];
  Directory? destination;
  File? partialFile;

  @override
  String get id => 'manual';

  @override
  Future<DownloadPreview> inspect(Uri source) async =>
      const DownloadPreview(title: 'Manual Song', suggestedFileName: 'manual');

  @override
  Stream<DownloadEvent> download(DownloadRequest req) async* {
    requests.add(req);
    final dir = destination!;
    await dir.create(recursive: true);
    partialFile = File('${dir.path}/${req.fileName}.part')
      ..writeAsBytesSync(const [1, 2, 3]);
    try {
      yield* _controller.stream;
    } finally {
      // Provider contract: cancel removes partial output.
      final file = partialFile;
      if (file != null && await file.exists()) await file.delete();
      unawaited(_controller.close());
      _controller = StreamController<DownloadEvent>();
    }
  }

  void emitProgress(int received, int total) =>
      _controller.add(DownloadProgress(received: received, total: total));

  void complete(String filePath) =>
      _controller.add(DownloadCompleted(filePath: filePath));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory fixtureRoot;
  late LibraryStore store;
  late FakeProbe probe;
  final managers = <DownloadManager>[];

  setUp(() async {
    fixtureRoot = await Directory.systemTemp.createTemp('mono_p4_downloads');
    store = LibraryStore(
      rootDirFactory: () async => Directory('${fixtureRoot.path}/root'),
    );
    probe = FakeProbe();
  });

  tearDown(() async {
    for (final manager in managers) {
      manager.dispose();
    }
    managers.clear();
    probe.dispose();
    try {
      await fixtureRoot.delete(recursive: true);
    } on FileSystemException catch (_) {
      // Best-effort cleanup.
    }
  });

  DownloadManager managerFor(
    List<SourceProvider> providers, {
    bool wifiOnly = true,
  }) {
    final manager = DownloadManager(
      providers: providers,
      libraryStore: store,
      connectivityProbe: probe,
      wifiOnly: wifiOnly,
    );
    managers.add(manager);
    return manager;
  }

  /// Reads one task out of a manager's notifier (tests use ≤2 tasks).
  DownloadTask taskOf(DownloadManager manager, [String? id]) {
    final tasks = manager.tasks.value;
    if (id == null) {
      expect(tasks, hasLength(1), reason: 'expected exactly one task');
      return tasks.single;
    }
    return tasks.firstWhere((t) => t.id == id);
  }

  Future<void> pumpUntil(bool Function() condition) async {
    for (var i = 0; i < 500; i++) {
      if (condition()) return;
      await Future<void>.delayed(Duration.zero);
    }
    fail('Condition not met within 500 event-loop turns');
  }

  group('progress → complete', () {
    test('persists task state, files and the library track', () async {
      final provider = FakeSourceProvider('fake')
        ..destination = await store.musicDirectory();
      final manager = managerFor([provider])..initialize();

      final id = await manager.enqueue(
        sourceUri: Uri.parse('https://youtube.com/watch?v=abc'),
      );
      expect(
        taskOf(manager).state,
        isIn([DownloadTaskState.queued, DownloadTaskState.running]),
      );

      await manager.idle;

      final task = taskOf(manager, id);
      expect(task.state, DownloadTaskState.completed);
      expect(task.progressBytes, 12);
      expect(task.totalBytes, 12);

      // Audio + sidecar artwork landed in Music/.
      final musicDir = await store.musicDirectory();
      final audio = File('${musicDir.path}/song.m4a');
      expect(await audio.exists(), isTrue);
      expect(await audio.length(), 12);
      expect(await File('${musicDir.path}/song.jpg').exists(), isTrue);

      // The completed track was registered in the manifest with metadata
      // from the preview and the sidecar artwork resolved.
      final tracks = await store.load();
      expect(tracks, hasLength(1));
      final track = tracks.single;
      expect(track.title, 'Song abc');
      expect(track.artist, 'Fake Artist');
      expect(track.durationMs, 42000);
      expect(track.source, TrackSource.downloaded);
      expect(track.artworkPath, isNotNull);
      expect(track.filePath, audio.path);
    });
  });

  group('wifi-only gate', () {
    test('holds queued tasks until an unmetered network appears', () async {
      probe.unmetered = false;
      final provider = FakeSourceProvider('fake')
        ..destination = await store.musicDirectory();
      final manager = managerFor([provider])..initialize();

      await manager.enqueue(sourceUri: Uri.parse('https://x/watch?v=gated'));
      await manager.idle;

      expect(
        taskOf(manager).state,
        DownloadTaskState.queued,
        reason: 'gate closed: transfer must not start',
      );
      expect(provider.requests, isEmpty);

      probe.setUnmetered(true); // connectivity listener re-kicks the pump
      await manager.idle;

      expect(taskOf(manager).state, DownloadTaskState.completed);
      expect(provider.requests, hasLength(1));
    });

    test('setWifiOnly(false) unblocks immediately', () async {
      probe.unmetered = false;
      final provider = FakeSourceProvider('fake')
        ..destination = await store.musicDirectory();
      final manager = managerFor([provider])..initialize();

      await manager.enqueue(sourceUri: Uri.parse('https://x/watch?v=off'));
      await manager.idle;
      expect(taskOf(manager).state, DownloadTaskState.queued);

      manager.setWifiOnly(false);
      await manager.idle;

      expect(taskOf(manager).state, DownloadTaskState.completed);
    });
  });

  group('pause / cancel / retry', () {
    test('pause aborts the transfer and retry restarts it', () async {
      final manual = ManualSourceProvider()
        ..destination = await store.musicDirectory();
      final manager = managerFor([manual])..initialize();

      final id = await manager.enqueue(
        sourceUri: Uri.parse('https://x/watch?v=song'),
      );
      await pumpUntil(
        () => taskOf(manager, id).state == DownloadTaskState.running,
      );
      manual.emitProgress(1, 10);
      await pumpUntil(() => taskOf(manager, id).progressBytes == 1);

      expect(await manager.pause(id), isTrue);
      expect(taskOf(manager, id).state, DownloadTaskState.paused);
      expect(
        await manual.partialFile!.exists(),
        isFalse,
        reason: 'provider cleanup must remove partial bytes on abort',
      );

      // Retry restarts from zero; this time let it finish.
      final doneFile = File('${(await store.musicDirectory()).path}/manual.m4a')
        ..writeAsBytesSync(const [1, 2, 3, 4]);
      expect(await manager.retry(id), isTrue);
      await pumpUntil(
        () => taskOf(manager, id).state == DownloadTaskState.running,
      );
      manual.complete(doneFile.path);
      await manager.idle;

      final task = taskOf(manager, id);
      expect(task.state, DownloadTaskState.completed);
      expect((await store.load()).single.filePath, doneFile.path);
    });

    test('cancel is terminal but retry can requeue it', () async {
      final manual = ManualSourceProvider()
        ..destination = await store.musicDirectory();
      final manager = managerFor([manual])..initialize();

      final id = await manager.enqueue(
        sourceUri: Uri.parse('https://x/watch?v=bye'),
      );
      await pumpUntil(
        () => taskOf(manager, id).state == DownloadTaskState.running,
      );

      await pumpUntil(() => manual.partialFile != null);
      expect(await manager.cancel(id), isTrue);
      expect(taskOf(manager, id).state, DownloadTaskState.canceled);
      expect(await manual.partialFile!.exists(), isFalse);

      expect(await manager.retry(id), isTrue);
      expect(
        taskOf(manager, id).state,
        isIn([DownloadTaskState.queued, DownloadTaskState.running]),
      );
      await manager.cancel(id);
    });
  });

  group('failure handling', () {
    test('failed tasks surface messages and are retryable', () async {
      final provider = FakeSourceProvider('fake')
        ..destination = await store.musicDirectory()
        ..failDownload = true;
      final manager = managerFor([provider])..initialize();

      final id = await manager.enqueue(
        sourceUri: Uri.parse('https://x/watch?v=fail'),
      );
      await manager.idle;

      final task = taskOf(manager, id);
      expect(task.state, DownloadTaskState.failed);
      expect(task.errorMessage, 'boom');
      expect(
        await store.load(),
        isEmpty,
        reason: 'failed downloads must not register tracks',
      );

      provider.failDownload = false;
      expect(await manager.retry(id), isTrue);
      await manager.idle;

      expect(taskOf(manager, id).state, DownloadTaskState.completed);
    });
  });

  group('provider selection', () {
    test('first capable provider wins; unsupported ones are skipped', () async {
      final broken = FakeSourceProvider('broken')..failInspect = true;
      final good = FakeSourceProvider('good')
        ..destination = await store.musicDirectory();
      final manager = managerFor([broken, good])..initialize();

      await manager.enqueue(sourceUri: Uri.parse('https://x/watch?v=pick'));
      await manager.idle;

      expect(broken.inspectCalls, 1);
      expect(good.inspectCalls, 1);
      expect(good.requests, hasLength(1));
      expect(taskOf(manager).state, DownloadTaskState.completed);
    });
  });

  group('persistence across restarts', () {
    test('task states survive a fresh manager over the same store', () async {
      final good = FakeSourceProvider('good')
        ..destination = await store.musicDirectory();
      final failing = FakeSourceProvider('failing')
        ..destination = await store.musicDirectory()
        ..failDownload = true;
      final manager = managerFor([good, failing])..initialize();

      await manager.enqueue(sourceUri: Uri.parse('https://x/watch?v=ok'));
      await manager.enqueue(sourceUri: Uri.parse('https://x/watch?v=nope'));
      await manager.idle;

      final statesByTitle = {
        for (final t in manager.tasks.value) t.title: t.state,
      };
      expect(statesByTitle['Song ok'], DownloadTaskState.completed);
      expect(statesByTitle['Song nope'], DownloadTaskState.failed);

      // Fresh manager over the same root: states preserved verbatim.
      final revived = managerFor([good, failing])..initialize();
      await revived.idle;
      final revivedStates = {
        for (final t in revived.tasks.value) t.title: t.state,
      };
      expect(revivedStates['Song ok'], DownloadTaskState.completed);
      expect(revivedStates['Song nope'], DownloadTaskState.failed);
    });

    test('a task persisted as running normalizes back to queued', () async {
      final root = await store.rootDirectory();
      await LibraryStore.ensureDir(root.path);
      await File('${root.path}/download-tasks.json').writeAsString(
        jsonEncode({
          'schemaVersion': 1,
          'tasks': [
            {
              'id': 'dl-crash',
              'sourceUri': 'https://x/watch?v=crash',
              'title': 'Crashed Song',
              'fileName': 'crashed song',
              'state': 'running',
              'progressBytes': 5,
              'totalBytes': 0,
              'createdAt': DateTime.now().toIso8601String(),
            },
          ],
        }),
      );

      final provider = FakeSourceProvider('fake')
        ..destination = await store.musicDirectory();
      final manager = managerFor([provider])..initialize();
      await manager.idle;

      // Normalized to queued on restore, then the pump legitimately ran it
      // to completion — proving both the normalization and resumption.
      expect(taskOf(manager).title, 'Crashed Song');
      expect(taskOf(manager).state, DownloadTaskState.completed);
    });
  });
}
