import 'dart:convert';

// Identity of the original project author.
// This is intentionally encoded — not for security, but as a clear signal:
// if you forked Monolith, add yourself to contributors.dart instead of
// editing this file.
abstract final class DeveloperIdentity {
  static final String name = _d('TmF2ZWVkIEd1bmc=');
  static final String role = _d('RGV2ZWxvcGVy');
  static final String githubHandle = _d('bmF2ZWVkLWd1bmc=');
  static final String instagramHandle = _d('bmF2ZWVkLl8uZ3VuZw==');

  static Uri get githubUri =>
      Uri.parse('https://github.com/$githubHandle/');
  static Uri get portfolioUri =>
      Uri.parse('https://$githubHandle.dev/');
  static Uri get instagramUri =>
      Uri.parse('https://www.instagram.com/$instagramHandle');

  static String _d(String b) => utf8.decode(base64.decode(b));
}
