import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../../../domain/models/download_task.dart';
import '../../../domain/models/track.dart';
import '../storage/library_store.dart';
import '../../repositories/import_export_repository.dart'
    show ImportExportRepository;
import 'source_provider.dart';

/// Network-gate seam so tests can fake connectivity without platform
/// channels. The production implementation wraps `connectivity_plus`
/// (see [ConnectivityPlusProbe]).
abstract interface class ConnectivityProbe {
  /// True when the current connection is suitable for large downloads
  /// (Wi-Fi or ethernet).
  Future<bool> isUnmetered();

  /// Emits whenever the connection type may have changed.
  Stream<void> get changes;
}

/// Real probe over `connectivity_plus`. Injected by default; tests substitute
/// a fake [ConnectivityProbe] instead of subclassing [Connectivity] (whose
/// constructors are private).
class ConnectivityPlusProbe implements ConnectivityProbe {
  ConnectivityPlusProbe({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<bool> isUnmetered() async {
    try {
      final results = await _connectivity.checkConnectivity();
      return results.contains(ConnectivityResult.wifi) ||
          results.contains(ConnectivityResult.ethernet);
    } catch (_) {
      // Fail closed: never burn metered data on an unknown network state.
      return false;
    }
  }

  @override
  Stream<void> get changes => _connectivity.onConnectivityChanged;
}

/// Persistent download queue for Monolith 2.0.
///
/// Responsibilities:
/// - **Provider-agnostic orchestration** — sources are resolved through
///   [SourceProvider]; the first provider whose `inspect` succeeds owns the
///   task.
/// - **Persistence** — the task list survives restarts via an atomic JSON
///   file next to the library manifest (`download-tasks.json`). Tasks found
///   in `running` state after a crash are normalized back to `queued`.
/// - **Wi-Fi-only gate** — when enabled, byte transfers wait for an unmetered
///   connection; metadata inspection still runs so titles resolve instantly.
/// - **Honest pause semantics** — YouTube streams are not resumable, so
///   pause/cancel aborts the transfer (the provider deletes partial bytes)
///   and retry restarts from zero.
/// - **Library registration** — completed downloads become domain [Track]s
///   persisted through [LibraryStore].
///
/// Tasks are processed strictly one at a time to keep network/CPU pressure
/// predictable on low-end hardware (rebuild plan §3.4).
class DownloadManager {
  DownloadManager({
    required List<SourceProvider> providers,
    required LibraryStore libraryStore,
    ConnectivityProbe? connectivityProbe,
    this.wifiOnly = true,
  }) : _providers = providers,
       _libraryStore = libraryStore,
       _probe = connectivityProbe ?? ConnectivityPlusProbe();

  static const String _tasksFileName = 'download-tasks.json';
  static const int _schemaVersion = 1;

  /// UI progress refresh cadence — byte counters update far more often than
  /// a progress bar needs to repaint.
  static const Duration _progressNotifyInterval = Duration(milliseconds: 250);

  final List<SourceProvider> _providers;
  final LibraryStore _libraryStore;
  final ConnectivityProbe _probe;

  /// When true, transfers only start on unmetered networks.
  bool wifiOnly;

  /// Insertion-ordered task table; also the source of truth for persistence.
  final Map<String, DownloadTask> _tasks = {};

  /// In-memory extras that do not belong in the persisted domain model:
  /// preview metadata and the provider that claimed each task.
  final Map<String, DownloadPreview> _previews = {};
  final Map<String, SourceProvider> _providerForTask = {};

  /// Observable snapshot for the downloads UI.
  final ValueNotifier<List<DownloadTask>> tasks = ValueNotifier(const []);

  bool _disposed = false;
  Future<void>? _initialization;
  Future<void> _pendingPersist = Future<void>.value();
  String? _activeTaskId;
  StreamSubscription<DownloadEvent>? _activeSubscription;
  final Map<String, Completer<void>> _runCompleters = {};
  Future<void>? _drainFuture;
  StreamSubscription<void>? _connectivitySub;
  DateTime _lastProgressNotify = DateTime.fromMillisecondsSinceEpoch(0);

  /// Loads persisted tasks, normalizes interrupted runs and starts listening
  /// for connectivity changes. Safe to call multiple times.
  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    await _restore();
    if (_disposed) return;
    _connectivitySub = _probe.changes.listen((_) => _kickPump());
    _kickPump();
  }

  // ------------------------------------------------------------------
  // Public queue operations
  // ------------------------------------------------------------------

  /// Inspects [sourceUri], registers a queued task and kicks the pump.
  ///
  /// Inspection happens up front (before the Wi-Fi gate) because it is a
  /// tiny metadata request — it buys instant, human-readable queue entries.
  /// Throws when no provider can handle the URI.
  Future<String> enqueue({
    required Uri sourceUri,
    String? title,
    String? fileName,
  }) async {
    _ensureAlive();
    await initialize();
    final resolved = await _resolveProvider(sourceUri);
    final provider = resolved.$1;
    final preview = resolved.$2;
    _ensureAlive();

    final id =
        'dl-${DateTime.now().microsecondsSinceEpoch}-${sourceUri.hashCode}';
    final sanitizedBaseName = ImportExportRepository.sanitizeFileName(
      (fileName != null && fileName.trim().isNotEmpty)
          ? fileName
          : preview.suggestedFileName,
    );

    _tasks[id] = DownloadTask(
      id: id,
      sourceUri: sourceUri.toString(),
      title: (title != null && title.trim().isNotEmpty)
          ? title.trim()
          : preview.title,
      fileName: sanitizedBaseName,
      state: DownloadTaskState.queued,
      createdAt: DateTime.now(),
    );
    _previews[id] = preview;
    _providerForTask[id] = provider;

    _notify();
    await _persist();
    _kickPump();
    return id;
  }

  /// Pauses a queued or running task. Running transfers are aborted (partial
  /// bytes deleted by the provider); retry later restarts from scratch.
  Future<bool> pause(String taskId) async {
    _ensureAlive();
    final task = _tasks[taskId];
    if (task == null) return false;
    switch (task.state) {
      case DownloadTaskState.running:
        _replaceTask(taskId, state: DownloadTaskState.paused);
        await _abortActiveRun(taskId);
      case DownloadTaskState.queued:
        _replaceTask(taskId, state: DownloadTaskState.paused);
      default:
        return false;
    }
    await _persist();
    return true;
  }

  /// Cancels a queued or running task. Like pause, but terminal — use
  /// [retry] to requeue.
  Future<bool> cancel(String taskId) async {
    _ensureAlive();
    final task = _tasks[taskId];
    if (task == null) return false;
    switch (task.state) {
      case DownloadTaskState.running:
        _replaceTask(taskId, state: DownloadTaskState.canceled);
        await _abortActiveRun(taskId);
      case DownloadTaskState.queued:
      case DownloadTaskState.paused:
        _replaceTask(taskId, state: DownloadTaskState.canceled);
      default:
        return false;
    }
    await _persist();
    return true;
  }

  /// Requeues a failed, canceled or paused task. Because source streams are
  /// not resumable this restarts the transfer from zero — documented, honest
  /// behaviour rather than a fake resume.
  Future<bool> retry(String taskId) async {
    _ensureAlive();
    final task = _tasks[taskId];
    if (task == null) return false;
    switch (task.state) {
      case DownloadTaskState.failed:
      case DownloadTaskState.canceled:
      case DownloadTaskState.paused:
        _replaceTask(
          taskId,
          state: DownloadTaskState.queued,
          errorMessage: null,
          progressBytes: 0,
        );
        await _persist();
        _kickPump();
        return true;
      default:
        return false;
    }
  }

  /// Updates the Wi-Fi-only preference at runtime and re-evaluates the gate.
  void setWifiOnly(bool enabled) {
    _ensureAlive();
    wifiOnly = enabled;
    if (enabled) return; // Tightening the gate never unblocks anything.
    _kickPump();
  }

  /// Waits until the pump has fully drained (or is gated). Test convenience.
  Future<void> get idle async {
    await initialize();
    // Give scheduled pumps (e.g. from a connectivity listener) a tick to
    // start before waiting them out.
    await Future<void>.delayed(Duration.zero);
    while (true) {
      final future = _drainFuture;
      if (future == null) return;
      await future;
      await Future<void>.delayed(Duration.zero);
    }
  }

  void dispose() {
    _disposed = true;
    unawaited(_connectivitySub?.cancel());
    _connectivitySub = null;
    final sub = _activeSubscription;
    _activeSubscription = null;
    _activeTaskId = null;
    unawaited(sub?.cancel());
    for (final completer in _runCompleters.values) {
      _complete(completer);
    }
    _runCompleters.clear();
    tasks.dispose();
  }

  // ------------------------------------------------------------------
  // Pump / task execution
  // ------------------------------------------------------------------

  void _kickPump() {
    if (_disposed) return;
    _drainFuture ??= Future<void>(_drain);
  }

  DownloadTask? _nextQueued() {
    for (final task in _tasks.values) {
      if (task.state == DownloadTaskState.queued) return task;
    }
    return null;
  }

  /// True when the last drain stopped because the Wi-Fi gate was closed.
  /// The connectivity listener — not a busy re-kick loop — owns resumption.
  bool _stoppedOnGate = false;

  Future<void> _drain() async {
    try {
      while (!_disposed) {
        final next = _nextQueued();
        if (next == null) {
          _stoppedOnGate = false;
          break;
        }
        if (wifiOnly && !await _probe.isUnmetered()) {
          // Leave the task queued; the connectivity listener re-kicks us.
          _stoppedOnGate = true;
          return;
        }
        _stoppedOnGate = false;
        await _runTask(next);
      }
    } finally {
      _drainFuture = null;
    }
    // Teardown-race re-kick: a task may have been enqueued/retried while the
    // final task was unwinding. Never spins when gated (flag guards it).
    if (!_disposed && !_stoppedOnGate && _nextQueued() != null) {
      _kickPump();
    }
  }

  Future<void> _runTask(DownloadTask task) async {
    final id = task.id;

    var provider = _providerForTask[id];
    if (provider == null) {
      // Restored after restart: re-resolve the provider and preview.
      try {
        final uri = Uri.parse(task.sourceUri);
        final resolved = await _resolveProvider(uri);
        provider = resolved.$1;
        _providerForTask[id] = provider;
        _previews[id] ??= resolved.$2;
      } catch (error) {
        _replaceTask(
          id,
          state: DownloadTaskState.failed,
          errorMessage: '$error',
        );
        await _persist();
        return;
      }
    }

    _replaceTask(id, state: DownloadTaskState.running, errorMessage: null);
    _notify();
    await _persist();

    if (_disposed || _tasks[id]?.state != DownloadTaskState.running) return;
    final request = DownloadRequest(
      id: id,
      sourceUri: Uri.parse(_tasks[id]!.sourceUri),
      fileName: _tasks[id]!.fileName,
    );

    final done = Completer<void>();
    _runCompleters[id] = done;
    _activeTaskId = id;

    Future<void> handleEvent(DownloadEvent event) async {
      if (_disposed || _tasks[id]?.state != DownloadTaskState.running) return;
      switch (event) {
        case DownloadProgress(received: final received, total: final total):
          _applyProgress(id, received, total);
        case DownloadCompleted(filePath: final filePath):
          await _finishCompleted(id, filePath);
          _complete(done);
        case DownloadFailed(message: final message):
          _replaceTask(
            id,
            state: DownloadTaskState.failed,
            errorMessage: message,
          );
          _notify();
          _complete(done);
      }
    }

    Future<void> events = Future<void>.value();
    final subscription = provider
        .download(request)
        .listen(
          (event) {
            events = events.then((_) => handleEvent(event)).catchError((
              Object error,
            ) {
              _replaceTask(
                id,
                state: DownloadTaskState.failed,
                errorMessage: YoutubeNormalize.error(error),
              );
              _complete(done);
            });
          },
          onError: (Object error) async {
            _replaceTask(
              id,
              state: DownloadTaskState.failed,
              errorMessage: YoutubeNormalize.error(error),
            );
            _notify();
            _complete(done);
          },
          onDone: () => unawaited(events.whenComplete(() => _complete(done))),
          cancelOnError: false,
        );
    _activeSubscription = subscription;

    await done.future;
    await subscription.cancel();
    await events;
    if (_disposed) return;

    _runCompleters.remove(id);
    _activeSubscription = null;
    _activeTaskId = null;

    // A stream that ended without any terminal event counts as a failure.
    final current = _tasks[id];
    if (current != null && current.state == DownloadTaskState.running) {
      _replaceTask(
        id,
        state: DownloadTaskState.failed,
        errorMessage: 'The source ended without producing a file.',
      );
      _notify();
    }
    await _persist();
  }

  Future<void> _abortActiveRun(String taskId) async {
    if (_activeTaskId != taskId) return;
    _activeTaskId = null;
    final sub = _activeSubscription;
    _activeSubscription = null;
    // Cancelling drives the provider's finally block, which deletes partial
    // output. Await it so callers observe cleanup completion.
    await sub?.cancel();
    _complete(_runCompleters[taskId]);
  }

  void _applyProgress(String taskId, int received, int total) {
    final task = _tasks[taskId];
    if (task == null || task.state != DownloadTaskState.running) return;
    _tasks[taskId] = task.copyWith(
      progressBytes: received,
      totalBytes: total > 0 ? total : task.totalBytes,
    );
    final now = DateTime.now();
    if (now.difference(_lastProgressNotify) >= _progressNotifyInterval) {
      _lastProgressNotify = now;
      _notify();
    }
  }

  Future<void> _finishCompleted(String taskId, String filePath) async {
    final task = _tasks[taskId];
    if (task == null || task.state != DownloadTaskState.running) return;
    await _registerTrackInLibrary(taskId, filePath);
    _replaceTask(
      taskId,
      state: DownloadTaskState.completed,
      progressBytes: task.totalBytes > 0 ? task.totalBytes : task.progressBytes,
    );
    _notify();
  }

  /// Builds the domain [Track] for a finished download and merges it into
  /// the library manifest (deduplicated by canonical path).
  Future<void> _registerTrackInLibrary(String taskId, String filePath) async {
    final task = _tasks[taskId];
    if (task == null) return;
    final preview = _previews[taskId];

    final track = Track(
      id: 'dl-$taskId',
      title: task.title,
      artist: preview?.artist ?? 'Unknown',
      album: 'Downloads',
      durationMs: preview?.durationMs ?? 0,
      filePath: filePath,
      artworkPath: await _libraryStore.findArtworkForAudio(filePath),
      artworkUrl: preview?.artworkUrl,
      source: TrackSource.downloaded,
      addedAt: DateTime.now(),
    );

    final existing = await _libraryStore.load();
    final canonicalPath = LibraryStore.canonical(filePath);
    final merged = [...existing];
    final index = merged.indexWhere(
      (t) => LibraryStore.canonical(t.filePath) == canonicalPath,
    );
    if (index >= 0) {
      merged[index] = track;
    } else {
      merged.add(track);
    }
    await _libraryStore.save(merged);
  }

  // ------------------------------------------------------------------
  // State helpers
  // ------------------------------------------------------------------

  /// The domain model's copyWith cannot clear nullable fields, so terminal
  /// transitions rebuild the task explicitly.
  void _replaceTask(
    String taskId, {
    required DownloadTaskState state,
    String? errorMessage,
    int? progressBytes,
  }) {
    final task = _tasks[taskId];
    if (_disposed || task == null) return;
    _tasks[taskId] = DownloadTask(
      id: task.id,
      sourceUri: task.sourceUri,
      title: task.title,
      fileName: task.fileName,
      state: state,
      progressBytes: progressBytes ?? task.progressBytes,
      totalBytes: task.totalBytes,
      errorMessage: errorMessage,
      createdAt: task.createdAt,
    );
    _notify();
  }

  void _notify() {
    if (!_disposed) tasks.value = List.unmodifiable(_tasks.values);
  }

  void _complete(Completer<void>? completer) {
    if (completer == null || completer.isCompleted) return;
    completer.complete();
  }

  Future<(SourceProvider, DownloadPreview)> _resolveProvider(
    Uri sourceUri,
  ) async {
    Object? lastError;
    for (final provider in _providers) {
      try {
        final preview = await provider.inspect(sourceUri);
        return (provider, preview);
      } catch (error) {
        lastError = error;
      }
    }
    throw StateError(
      'No download provider can handle $sourceUri'
      '${lastError == null ? '' : ' (last error: $lastError)'}',
    );
  }

  void _ensureAlive() {
    if (_disposed) throw StateError('DownloadManager has been disposed.');
  }

  // ------------------------------------------------------------------
  // Persistence (atomic temp+rename, mirroring LibraryStore.save)
  // ------------------------------------------------------------------

  Future<File> _persistenceFile() async {
    final root = await _libraryStore.rootDirectory();
    await LibraryStore.ensureDir(root.path);
    return File('${root.path}/$_tasksFileName');
  }

  Future<void> _persist() {
    final next = _pendingPersist.then((_) => _persistNow());
    _pendingPersist = next.catchError((Object _) {});
    return next;
  }

  Future<void> _persistNow() async {
    if (_disposed) return;
    try {
      final file = await _persistenceFile();
      final payload = <String, dynamic>{
        'schemaVersion': _schemaVersion,
        'tasks': _tasks.values.map((task) => task.toJson()).toList(),
      };
      final json = const JsonEncoder.withIndent('  ').convert(payload);
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(json, flush: true);
      try {
        await temp.rename(file.path);
      } on FileSystemException {
        // Windows cannot rename onto an existing target.
        if (await file.exists()) await file.delete();
        await temp.rename(file.path);
      }
    } on FileSystemException {
      // Persistence is best-effort; the in-memory queue keeps working.
    }
  }

  Future<void> _restore() async {
    try {
      final file = await _persistenceFile();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return;
      final rawTasks = decoded['tasks'] as List<dynamic>? ?? const [];

      var changed = false;
      for (final item in rawTasks) {
        if (item is! Map<String, dynamic>) continue;
        final task = DownloadTask.fromJson(item);
        if (task.id.isEmpty || _tasks.containsKey(task.id)) continue;
        // A run interrupted by shutdown cannot still be running.
        if (task.state == DownloadTaskState.running) {
          _tasks[task.id] = task.copyWith(state: DownloadTaskState.queued);
          changed = true;
        } else {
          _tasks[task.id] = task;
        }
      }
      _notify();
      if (changed) await _persist();
    } on FormatException {
      // A corrupt queue file must not take the manager down; start empty.
    } on FileSystemException {
      // Unreadable storage — same story.
    }
  }
}

/// Error-normalization hook shared by the manager's stream-error path.
/// Delegates to the YouTube provider's mapping when available so messages
/// stay consistent regardless of which layer catches first.
class YoutubeNormalize {
  const YoutubeNormalize._();

  static String error(Object error) {
    final message = error.toString().trim().toLowerCase();
    if (message.contains('403') ||
        message.contains('forbidden') ||
        message.contains('sign in to confirm you') ||
        message.contains('challenge request')) {
      return 'The source blocked this download request (403 / anti-bot '
          'challenge), so Monolith stopped it before saving anything.';
    }
    return 'Download failed: $error';
  }
}
