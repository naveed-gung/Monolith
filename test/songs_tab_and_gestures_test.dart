import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monolith/src/app/state/app_controller.dart';
import 'package:monolith/src/core/models/music_models.dart';
import 'package:monolith/src/core/services/app_update_service.dart';
import 'package:monolith/src/core/services/download_store.dart';
import 'package:monolith/src/core/services/local_media_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  SharedPreferences.setMockInitialValues({});
  TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
        (call) async => null,
      );
  TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/connectivity'),
        (call) async => <String>['none'],
      );

  group('Monolith v1.2.0 Features & Enhancements', () {
    test('AppTab enum contains library, downloads, songs, search in order', () {
      expect(AppTab.values, [
        AppTab.library,
        AppTab.downloads,
        AppTab.songs,
        AppTab.search,
      ]);
    });

    testWidgets('dismissDownloadTask and clearLibraryError work correctly', (tester) async {
      final controller = await tester.runAsync(() async {
        final c = MonolithController(
          localMediaService: _FakeLocalMediaService([]),
          downloadStore: _FakeDownloadStore([]),
        );
        return c;
      });

      expect(controller, isNotNull);
      controller!.dismissDownloadTask('non-existent');
      expect(controller.downloadTasks, isEmpty);

      controller.clearLibraryError();
      expect(controller.libraryError, isNull);

      controller.selectTab(AppTab.songs);
      expect(controller.currentTab, AppTab.songs);
    });

    test('AppUpdateService version is bumped to 1.4.0', () {
      expect(AppUpdateService.currentVersion, '1.4.0');
    });

    test('clearStaleAppCache runs without errors', () async {
      final service = AppUpdateService.instance;
      final freed = await service.clearStaleAppCache();
      expect(freed, isNonNegative);
    });
  });
}

class _FakeLocalMediaService extends LocalMediaService {
  _FakeLocalMediaService(this._tracks);
  final List<Track> _tracks;

  @override
  Future<LocalMediaSnapshot> loadTracks({
    bool retryRequest = false,
    bool requestPermission = true,
  }) async {
    return LocalMediaSnapshot(
      permissionGranted: true,
      tracks: _tracks,
      error: null,
    );
  }

  @override
  Future<void> scanMedia(String path) async {}
}

class _FakeDownloadStore extends DownloadStore {
  _FakeDownloadStore(this._tracks);
  List<Track> _tracks;

  @override
  Future<List<Track>> loadTracks() async => _tracks;

  @override
  Future<void> saveTracks(List<Track> tracks) async {
    _tracks = tracks;
  }
}
