import 'package:flutter_test/flutter_test.dart';
import 'package:monolith/src/core/services/app_update_service.dart';

void main() {
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
