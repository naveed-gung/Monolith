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
    processId = request.processId;
    return result.future;
  }

  @override
  Future<bool> cancelDownload(String processId) async => false; // Provider still resolving metadata.
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
  test(
    'audio is audible before play future completes and refresh preserves playback',
    () async {
      await controller.togglePlayback().timeout(const Duration(seconds: 1));
      expect(player.ended.isCompleted, isFalse);
      expect(player.volumeAtPlay, greaterThan(0));
      expect(player.playing, isTrue);
      controller.selectTrack(controller.tracks.last, openPlayer: false);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(
        player.volumeAtPlay,
        greaterThan(0),
        reason:
            'Changing sources must not await song completion at zero volume.',
      );
      expect(player.volume, closeTo(0.84, 0.01));
      final initialLoads = player.loads;
      await controller.refreshLibrary();
      expect(player.loads, initialLoads);
      expect(player.playing, isTrue);
    },
  );
  test(
    'finishing a download adds it immediately without replacing the playing song',
    () async {
      await controller.togglePlayback();
      final playingId = controller.currentTrack!.id;
      final loads = player.loads;
      await controller.startAudioDownload(
        preview: const DownloadPreview(
          url: 'https://youtube.com/watch?v=test',
          title: 'Downloaded',
          suggestedFileName: 'Downloaded',
          duration: Duration(seconds: 19),
        ),
        fileName: 'Downloaded',
      );
      await Future<void>.delayed(Duration.zero);
      final finished = File('${root.path}/finished.m4a')
        ..writeAsBytesSync([1, 2, 3]);
      downloader.result.complete(
        DownloadResult(
          status: OperationStatus.success,
          outputPath: finished.path,
        ),
      );
      for (var i = 0; i < 30 && controller.downloadedTracks.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(controller.downloadedTracks.single.title, 'Downloaded');
      expect(controller.downloadedTracks.single.duration.inSeconds, 19);
      expect(controller.currentTrack!.id, playingId);
      expect(player.loads, loads);
      expect(player.playing, isTrue);
      await controller.refreshLibrary();
      expect(controller.downloadedTracks.length, 1);
    },
  );

  test(
    'explicitly selecting the loaded song rewinds without reloading',
    () async {
      final loads = player.loads;
      controller.selectTrack(controller.currentTrack!, openPlayer: false);
      await Future<void>.delayed(Duration.zero);
      expect(player.rewinds, 1);
      expect(player.loads, loads);
      expect(player.playing, isTrue);
    },
  );

  test(
    'cancel during preparation is terminal and dismissed jobs cannot return',
    () async {
      await controller.startAudioDownload(
        preview: const DownloadPreview(
          url: 'https://youtube.com/watch?v=test',
          title: 'Test',
          suggestedFileName: 'Test',
        ),
        fileName: 'Test',
      );
      await Future<void>.delayed(Duration.zero);
      final id = controller.downloadTasks.single.processId;
      await controller.cancelDownload(id);
      expect(
        controller.downloadTasks.single.status,
        DownloadTaskStatus.cancelled,
      );
      downloader.states.add(
        DownloadState(processId: id, state: DownloadStateType.started),
      );
      expect(
        controller.downloadTasks.single.status,
        DownloadTaskStatus.cancelled,
      );
      controller.dismissDownloadTask(id);
      downloader.states.add(
        DownloadState(processId: id, state: DownloadStateType.completed),
      );
      downloader.result.complete(
        DownloadResult(status: OperationStatus.cancelled),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.downloadTasks, isEmpty);
      expect(controller.downloadedTracks, isEmpty);
      expect(controller.offlineTracks.length, 2);
    },
  );
}
