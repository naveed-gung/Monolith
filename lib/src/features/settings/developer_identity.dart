// Original project author identity.
//
// Encoding: each byte b at index i is stored as ((b ^ key[i % keyLen]) + i) & 0xFF
// Key is split across _ka and _kb and assembled only at decode time.
//
// If you forked Monolith: do NOT edit here. Add yourself to contributors.dart.

import 'dart:io';

abstract final class DeveloperIdentity {
  // Encoded payloads — raw ints, not strings.
  static const List<int> _n  = [0x05,0x7e,0x43,0xf2,0x9b,0x36,0xc4,0x2b,0xac,0x4a,0xca];
  static const List<int> _rl = [0x0f,0x7a,0x43,0xf2,0xa2,0x3f,0xf4,0x0d,0xab];
  static const List<int> _gh = [0x25,0x7e,0x43,0xf2,0x9b,0x36,0xb9,0x0b,0xac,0x4a,0xca];
  static const List<int> _ig = [0x25,0x7e,0x43,0xf2,0x9b,0x36,0xb6,0x43,0x07,0x51,0xdc,0x70,0x9b];
  // dev.naveed_gung.monolith (Android — underscore; hyphens illegal in Java package names)
  static const List<int> _biA = [0x2f,0x7a,0x43,0xa7,0xa0,0x39,0xee,0x0d,0xbc,0x54,0x02,0x77,0xa9,0x32,0x89,0x28,0xf7,0xae,0x4d,0x04,0x23,0xcd,0x71,0xe6];
  // dev.naveed-gung.monolith (iOS — hyphen, matches naveed-gung.dev domain)
  static const List<int> _biI = [0x2f,0x7a,0x43,0xa7,0xa0,0x39,0xee,0x0d,0xbc,0x54,0x94,0x77,0xa9,0x32,0x89,0x28,0xf7,0xae,0x4d,0x04,0x23,0xcd,0x71,0xe6];

  // Key halves — never stored whole in source.
  static const List<int> _ka = [0x4b,0x1c,0x37,0x8a,0xf2,0x55];
  static const List<int> _kb = [0x9e,0x63,0xd1,0x2f,0xa7,0x0b,0xe8];

  static String get name            => _s(_n);
  static String get role            => _s(_rl);
  static String get githubHandle    => _s(_gh);
  static String get instagramHandle => _s(_ig);
  static String get bundleId        => _s(Platform.isAndroid ? _biA : _biI);

  static Uri get githubUri    => Uri.parse('https://github.com/$githubHandle/');
  static Uri get portfolioUri => Uri.parse('https://$githubHandle.dev/');
  static Uri get instagramUri =>
      Uri.parse('https://www.instagram.com/$instagramHandle');

  // Decode: subtract index, XOR with cycling key assembled from halves.
  static String _s(List<int> b) {
    final k = [..._ka, ..._kb];
    return String.fromCharCodes(
      List.generate(b.length, (i) => ((b[i] - i) & 0xFF) ^ k[i % k.length]),
    );
  }
}
