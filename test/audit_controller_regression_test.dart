import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:monolith/src/app/state/app_controller.dart';
import 'package:monolith/src/core/models/music_models.dart';
import 'package:monolith/src/core/services/download_store.dart';
import 'package:monolith/src/core/services/local_media_service.dart';
import 'package:monolith/src/core/services/media_downloader.dart';
import 'package:monolith/src/core/services/media_downloader_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Player implements AudioPlayer {
  final ended = Completer<void>();
  int loads = 0;
  int rewinds = 0;
  @override
  Future<void> seek(Duration? position, {int? index}) async {
    if (position == Duration.zero) rewinds++;
  }

  double volumeAtPlay = -1;
  @override
  double volume = 1;
  @override
  bool playing = false;
  @override
  Duration? get duration => const Duration(seconds: 84);
  @override
  Stream<PlayerState> get playerStateStream => const Stream.empty();
  @override
  Stream<Duration?> get durationStream => const Stream.empty();
  @override
  Stream<Duration> createPositionStream({
    int steps = 800,
    Duration minPeriod = const Duration(milliseconds: 16),
    Duration maxPeriod = const Duration(milliseconds: 200),
  }) => const Stream.empty();
  @override
  Future<Duration?> setAudioSource(
    AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    loads++;
    return duration;
  }

  @override
  Future<void> setVolume(double value) async {
    volume = value;
  }

  @override
  Future<void> play() {
    playing = true;
    volumeAtPlay = volume;
    return ended.future;
  }

  @override
  Future<void> pause() async {
    playing = false;
  }

  @override
  Future<void> stop() async {
    playing = false;
  }

  @override
  Future<void> dispose() async {
    if (!ended.isCompleted) ended.complete();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Store extends DownloadStore {
  _Store(this.root, this.tracks);
  final Directory root;
  List<Track> tracks;
  @override
  Future<List<Track>> loadTracksMergingDisk() async => tracks;
  @override
  Future<void> saveTracks(List<Track> value) async {
    tracks = value;
  }

  @override
  Future<Directory> getDownloadDirectory() async => root;
  @override
  Future<Map<Object?, Object?>> readAudioMetadata(String path) async => {};
}

class _Media extends LocalMediaService {
  @override
  Future<LocalMediaSnapshot> loadTracks({
    bool retryRequest = false,
    bool requestPermission = true,
  }) async => const LocalMediaSnapshot(permissionGranted: true, tracks: []);
}

class _Downloader implements MediaDownloader {
  final states = StreamController<DownloadState>.broadcast(sync: true);
  final result = Completer<DownloadResult>();
  String? processId;
  int requests = 0;
  bool cancelSucceeds = false;
  @override
  Stream<DownloadState> get onStateChanged => states.stream;
  @override
  Stream<DownloadProgress> get onProgress => const Stream.empty();
  @override
  Stream<DownloadError> get onError => const Stream.empty();
  @override
  Stream<LogMessage> get onLog => const Stream.empty();
  @override
  Future<InitResult> initialize({
    bool enableFFmpeg = true,
    bool enableAria2c = false,
  }) async => InitResult(success: true);
  @override
  Future<DownloadResult> download(DownloadRequest request) {
    requests++;
    processId = request.processId;
    return result.future;
  }

  @override
  Future<bool> cancelDownload(String processId) async => cancelSucceeds;
  @override
  void dispose() {
    states.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late _Player player;
  late _Downloader downloader;
  late MonolithController controller;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (_) async => ['wifi'],
    );
    root = await Directory.systemTemp.createTemp('monolith_live_regression');
    final audio = File('${root.path}/song.m4a')..writeAsBytesSync([1, 2, 3]);
    final track = Track(
      id: 'imported',
      title: 'Song',
      artist: 'Artist',
      album: 'Album',
      genre: '',
      duration: Duration.zero,
      colors: Track.paletteForSeed('song'),
      blurb: '',
      source: TrackSource.imported,
      filePath: audio.path,
    );
    player = _Player();
    downloader = _Downloader();
    controller = MonolithController(
      audioPlayer: player,
      downloadStore: _Store(root, [
        track,
        track.copyWith(
          id: 'second',
          filePath: audio.copySync('${root.path}/second.m4a').path,
        ),
      ]),
      localMediaService: _Media(),
      mediaDownloader: downloader,
    );
    await controller.whenReady;
  });
  tearDown(() async {
    controller.dispose();
    if (!downloader.result.isCompleted) {
      downloader.result.complete(
        DownloadResult(status: OperationStatus.cancelled),
      );
    }
    await Future<void>.delayed(Duration.zero);
    await root.delete(recursive: true);
  });

  test('playlists and favorites survive controller restart', () async {
    controller.createEmptyPlaylist('Road trip');
    controller.addTrackToPlaylist(
      track: controller.tracks.first,
      playlistName: 'Road trip',
    );
    controller.addTrackToPlaylist(
      track: controller.tracks.first,
      playlistName: 'Favorites',
    );
    final restarted = MonolithController(
      audioPlayer: _Player(),
      downloadStore: _Store(root, controller.tracks),
      localMediaService: _Media(),
      mediaDownloader: _Downloader(),
    );
    await restarted.whenReady;
    try {
      expect(restarted.playlistNames, contains('Road trip'));
      expect(restarted.tracksForPlaylist('Favorites'), hasLength(1));
    } finally {
      restarted.dispose();
    }
  });

  test('Wi-Fi-only also applies when retrying a failed download', () async {
    downloader.result.complete(DownloadResult(status: OperationStatus.error));
    await controller.startAudioDownload(
      preview: const DownloadPreview(
        url: 'https://example.com/audit',
        title: 'Audit',
        suggestedFileName: 'audit',
      ),
      fileName: 'audit',
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final task = controller.downloadTasks.single;
    expect(task.status, DownloadTaskStatus.failed);
    final initialRequests = downloader.requests;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity'),
          (_) async => ['mobile'],
        );
    try {
      await controller.retryDownload(task.processId);
    } on StateError {
      /* Expected refusal. */
    }
    expect(
      downloader.requests,
      initialRequests,
      reason:
          'Retry must not start a transfer over cellular with Wi-Fi-only enabled.',
    );
  });

  test('previous reverses next with shuffle enabled', () async {
    final tracks = [
      ...controller.tracks,
      controller.tracks.first.copyWith(id: 'third'),
    ];
    final c = MonolithController(
      audioPlayer: _Player(),
      downloadStore: _Store(root, tracks),
      localMediaService: _Media(),
      mediaDownloader: _Downloader(),
    );
    await c.whenReady;
    try {
      c.toggleShuffle();
      final start = c.currentTrack!.id;
      c.nextTrack();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      c.previousTrack();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(c.currentTrack!.id, start);
    } finally {
      c.dispose();
    }
  });

  test('Wi-Fi-only applies to resume without losing the paused task', () async {
    await controller.startAudioDownload(
      preview: const DownloadPreview(
        url: 'https://example.com/audit',
        title: 'Audit',
        suggestedFileName: 'audit',
      ),
      fileName: 'audit',
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final id = controller.downloadTasks.single.processId;
    downloader.states.add(
      DownloadState(processId: id, state: DownloadStateType.started),
    );
    downloader.cancelSucceeds = true;
    await controller.pauseDownload(id);
    expect(controller.downloadTasks.single.status, DownloadTaskStatus.paused);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity'),
          (_) async => ['mobile'],
        );
    await expectLater(controller.resumeDownload(id), throwsStateError);
    expect(downloader.requests, 1);
    expect(controller.downloadTasks.single.status, DownloadTaskStatus.paused);
  });

  test('repeat-off Up Next is empty on the final track', () async {
    controller.selectTrack(controller.tracks.last, autoplay: false);
    await Future<void>.delayed(Duration.zero);
    expect(controller.repeatMode, RepeatMode.off);
    expect(controller.upNextTracks, isEmpty);
  });

  test('repeated Music import does not duplicate the same song', () async {
    var callCount = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('monolith/media_import'),
      (call) async {
        if (call.method != 'importAllFromMusicLibrary') return null;
        final file = File('${root.path}/native-copy-${callCount++}.m4a')
          ..writeAsBytesSync([1, 2, 3]);
        return [
          {
            'status': 'copied',
            'sourceId': '42',
            'path': file.path,
            'title': 'Repeated song',
            'artist': 'Same artist',
            'durationMs': 30000,
          },
        ];
      },
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel('monolith/media_import'),
        null,
      ),
    );
    await controller.importAllFromMusicLibrary();
    await controller.importAllFromMusicLibrary();
    expect(
      controller.tracks.where((t) => t.title == 'Repeated song'),
      hasLength(1),
    );
  });

  test('favorites removal is persisted across restart', () async {
    final track = controller.tracks.first;
    controller.addTrackToPlaylist(track: track, playlistName: 'Favorites');
    var restarted = MonolithController(
      audioPlayer: _Player(),
      downloadStore: _Store(root, controller.tracks),
      localMediaService: _Media(),
      mediaDownloader: _Downloader(),
    );
    await restarted.whenReady;
    expect(restarted.tracksForPlaylist('Favorites'), hasLength(1));
    restarted.removeTrackFromPlaylist(track: track, playlistName: 'Favorites');
    restarted.dispose();
    restarted = MonolithController(
      audioPlayer: _Player(),
      downloadStore: _Store(root, controller.tracks),
      localMediaService: _Media(),
      mediaDownloader: _Downloader(),
    );
    await restarted.whenReady;
    expect(restarted.tracksForPlaylist('Favorites'), isEmpty);
    restarted.dispose();
  });

  test(
    'collection queue stays inside selected tracks and preserves order',
    () async {
      final first = controller.tracks.first;
      final last = controller.tracks.last;
      controller.selectTrack(last, autoplay: false, queue: [last, first]);
      expect(controller.upNextTracks.map((t) => t.id), [first.id]);
      controller.nextTrack();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(controller.currentTrack!.id, first.id);
      expect(controller.upNextTracks, isEmpty);
      controller.cycleRepeatMode();
      expect(controller.upNextTracks.single.id, last.id);
    },
  );

  test(
    'shuffle visits each track once then stops at repeat-off boundary',
    () async {
      controller.toggleShuffle();
      final first = controller.currentTrack!.id;
      final next = controller.upNextTracks.single.id;
      expect(next, isNot(first));
      controller.nextTrack();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(controller.currentTrack!.id, next);
      expect(controller.upNextTracks, isEmpty);
      controller.nextTrack();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(controller.currentTrack!.id, next);
    },
  );

  test(
    'distinct Music identities with identical titles remain separate',
    () async {
      var index = 0;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('monolith/media_import'),
        (call) async {
          if (call.method != 'importAllFromMusicLibrary') return null;
          final id = '${index++}';
          final file = File('${root.path}/distinct-$id.m4a')
            ..writeAsBytesSync([1, 2, 3]);
          return [
            {
              'status': 'copied',
              'sourceId': id,
              'path': file.path,
              'title': 'Same title',
              'artist': 'Same artist',
            },
          ];
        },
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          const MethodChannel('monolith/media_import'),
          null,
        ),
      );
      await controller.importAllFromMusicLibrary();
      await controller.importAllFromMusicLibrary();
      expect(
        controller.tracks.where((t) => t.title == 'Same title'),
        hasLength(2),
      );
    },
  );
}
