import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monolith/src/core/services/app_update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'downloaded IPA restores offline, without re-downloading or stuck progress',
    () async {
      SharedPreferences.setMockInitialValues({});
      final root = await Directory.systemTemp.createTemp('update_restore_');
      addTearDown(() => root.delete(recursive: true));
      final bytes = [0x50, 0x4b, 3, 4, ...List.filled(100, 0)];
      var requests = 0;
      final service = AppUpdateService(
        ios: true,
        supportDirectory: () async => root,
        clientFactory: () => MockClient((_) async {
          requests++;
          return http.Response.bytes(bytes, 200);
        }),
      );
      service.release = AppRelease(
        '9.0.0',
        Uri.parse(
          'https://github.com/naveed-gung/Monolith/releases/download/v9.0.0/monolith.ipa',
        ),
        bytes.length,
      );
      await service.download();
      expect(service.downloaded, isNotNull);
      expect(service.busy, isFalse);
      expect(service.isDownloading, isFalse);
      expect(service.progress, isNull);
      await service.download();
      expect(requests, 1, reason: 'A verified local IPA must be reused.');
      final restarted = AppUpdateService(
        ios: true,
        supportDirectory: () async => root,
      );
      await restarted.restoreDownloadedPackage();
      expect(restarted.downloaded?.path, service.downloaded?.path);
      expect(restarted.status, contains('ready to install'));
      await restarted.clearStaleAppCache();
      expect(await restarted.downloaded!.exists(), isTrue);
      service.dispose();
      restarted.dispose();
    },
  );
  test(
    'cancelling update preparation terminates without waiting for server',
    () async {
      SharedPreferences.setMockInitialValues({});
      final root = await Directory.systemTemp.createTemp('update_cancel_');
      addTearDown(() => root.delete(recursive: true));
      final requested = Completer<void>();
      final service = AppUpdateService(
        ios: true,
        supportDirectory: () async => root,
        clientFactory: () => MockClient((_) {
          requested.complete();
          return Completer<http.Response>().future;
        }),
      );
      service.release = AppRelease(
        '9.0.0',
        Uri.parse(
          'https://github.com/naveed-gung/Monolith/releases/download/v9.0.0/monolith.ipa',
        ),
        100,
      );
      final work = service.download();
      await requested.future;
      service.cancelDownload();
      await work.timeout(const Duration(seconds: 1));
      expect(service.busy, isFalse);
      expect(service.progress, isNull);
      expect(service.downloaded, isNull);
      expect(service.status, contains('cancelled'));
      service.dispose();
    },
  );

  test('selects only platform release assets from the configured repository', () {
    final json = <String, dynamic>{
      'tag_name': 'v1.2.0',
      'assets': [
        {
          'name': 'monolith.ipa',
          'browser_download_url':
              'https://github.com/naveed-gung/Monolith/releases/download/v1.2.0/monolith.ipa',
          'size': 25,
        },
        {
          'name': 'monolith.apk',
          'browser_download_url': 'https://evil.example/monolith.apk',
        },
      ],
    };
    expect(AppRelease.parse(json, ios: true)?.version, '1.2.0');
    expect(AppRelease.parse(json, ios: false), isNull);
    expect(AppRelease.parse({...json, 'prerelease': true}, ios: true), isNull);
    expect(
      AppRelease.parse({...json, 'tag_name': 'v1.2.0-beta'}, ios: true),
      isNull,
    );
  });
  test('compares numeric versions and installed build suffixes', () {
    expect(AppRelease.isNewer('1.10.0', '1.9.0+6'), isTrue);
    expect(AppRelease.isNewer('1.1.0', '1.1.0'), isFalse);
    expect(AppRelease.isNewer('1.0.9', '1.1.0'), isFalse);
  });
}
