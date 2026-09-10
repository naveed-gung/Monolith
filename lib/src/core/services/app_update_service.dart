import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class AppRelease {
  const AppRelease(this.version, this.url, this.size);
  final String version;
  final Uri url;
  final int size;

  static AppRelease? parse(Map<String, dynamic> json, {required bool ios}) {
    if (json['draft'] == true || json['prerelease'] == true) return null;
    final version = (json['tag_name'] as String? ?? '').replaceFirst(
      RegExp(r'^v'),
      '',
    );
    if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version)) return null;
    final extension = ios ? '.ipa' : '.apk';
    for (final raw in (json['assets'] as List? ?? const [])) {
      if (raw is! Map) continue;
      final name = raw['name'] as String? ?? '';
      final uri = Uri.tryParse(raw['browser_download_url'] as String? ?? '');
      if (name.toLowerCase() == 'monolith$extension' &&
          uri != null &&
          uri.scheme == 'https' &&
          uri.host == 'github.com' &&
          uri.path.startsWith('/naveed-gung/Monolith/releases/download/')) {
        return AppRelease(version, uri, (raw['size'] as num?)?.toInt() ?? 0);
      }
    }
    return null;
  }

  static bool isNewer(String latest, String current) {
    final a = latest.split('.').map(int.parse).toList();
    final b = current.split('+').first.split('.').map(int.parse).toList();
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
  }
}

class AppUpdateService extends ChangeNotifier {
  AppUpdateService({
    http.Client Function()? clientFactory,
    Future<Directory> Function()? supportDirectory,
    bool? ios,
  }) : _clientFactory = clientFactory ?? http.Client.new,
       _supportDirectory = supportDirectory ?? getApplicationSupportDirectory,
       isIOS = ios ?? Platform.isIOS;
  final http.Client Function() _clientFactory;
  final Future<Directory> Function() _supportDirectory;
  final bool isIOS;
  http.Client? _downloadClient;
  Completer<void>? _cancellation;
  bool get isDownloading => _downloadClient != null;
  static const _savedPackageKey = 'updates_downloaded_package';

  Future<T> _wait<T>(Future<T> work, Duration timeout) => Future.any<T>([
    work.timeout(timeout),
    _cancellation!.future.then<T>(
      (_) => throw StateError('Update download cancelled'),
    ),
  ]);

  void cancelDownload() {
    if (!isDownloading || _cancellation!.isCompleted) return;
    _cancellation!.complete();
    _downloadClient?.close();
    status = 'Cancelling update download…';
    notifyListeners();
  }

  Future<bool> _validPackage(File file, int size) async {
    if (!await file.exists() || (size > 0 && await file.length() != size)) {
      return false;
    }
    final handle = await file.open();
    try {
      final bytes = await handle.read(4);
      return bytes.length == 4 &&
          bytes[0] == 0x50 &&
          bytes[1] == 0x4b &&
          bytes[2] == 3 &&
          bytes[3] == 4;
    } finally {
      await handle.close();
    }
  }

  Future<File> _packageFile(AppRelease candidate) async {
    final root = await _supportDirectory();
    return File(
      '${root.path}/Updates/monolith-${candidate.version}.${isIOS ? 'ipa' : 'apk'}',
    );
  }

  Future<void> _rememberPackage(AppRelease candidate) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _savedPackageKey,
      jsonEncode({
        'tag_name': 'v${candidate.version}',
        'assets': [
          {
            'name': 'monolith.${isIOS ? 'ipa' : 'apk'}',
            'browser_download_url': candidate.url.toString(),
            'size': candidate.size,
          },
        ],
      }),
    );
  }

  Future<void> restoreDownloadedPackage() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = prefs.getString(_savedPackageKey);
      if (raw == null) return;
      final candidate = AppRelease.parse(
        jsonDecode(raw) as Map<String, dynamic>,
        ios: isIOS,
      );
      if (candidate == null ||
          !AppRelease.isNewer(candidate.version, currentVersion)) {
        return;
      }
      final file = await _packageFile(candidate);
      if (await _validPackage(file, candidate.size)) {
        release = candidate;
        downloaded = file;
        status = 'Version ${candidate.version} ready to install';
      }
    } catch (_) {
      /* Missing or obsolete cache never blocks startup. */
    }
    notifyListeners();
  }

  static final instance = AppUpdateService();
  static const currentVersion = '1.4.4';
  bool autoDownload = true;
  bool busy = false;
  double? progress;
  String status = 'Updates from GitHub';
  AppRelease? release;
  File? downloaded;
  bool updateInstalled = false;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    autoDownload = prefs.getBool('updates_wifi_auto') ?? true;

    await restoreDownloadedPackage();

    // Check if new version was installed and clear old temporary cache
    final lastVersion = prefs.getString('last_run_version');
    if (lastVersion != null && lastVersion != currentVersion) {
      await clearStaleAppCache();
    }
    await prefs.setString('last_run_version', currentVersion);

    notifyListeners();
    if (autoDownload) await check(automatic: true);
  }

  /// Removes stale temporary chunks, old update packages, and engine caches,
  /// strictly leaving the user's custom settings and downloaded music files intact.
  Future<int> clearStaleAppCache() async {
    var bytesFreed = 0;
    try {
      final root = await _supportDirectory();
      final updatesDir = Directory('${root.path}/Updates');
      if (await updatesDir.exists()) {
        await for (final entity in updatesDir.list(recursive: false)) {
          try {
            if (entity is File &&
                !isDownloading &&
                !p.equals(entity.path, downloaded?.path ?? '') &&
                RegExp(
                  r'monolith-\d+\.\d+\.\d+\.(ipa|apk)(\.part)?$',
                ).hasMatch(entity.path)) {
              bytesFreed += await entity.length();
              await entity.delete();
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
    return bytesFreed;
  }

  Future<void> setAutomatic(bool value) async {
    autoDownload = value;
    await (await SharedPreferences.getInstance()).setBool(
      'updates_wifi_auto',
      value,
    );
    notifyListeners();
    if (value) await check(automatic: true);
  }

  Future<void> check({bool automatic = false}) async {
    if (busy) return;
    busy = true;
    status = 'Checking GitHub…';
    notifyListeners();
    try {
      final response = await http
          .get(
            Uri.parse(
              'https://api.github.com/repos/naveed-gung/Monolith/releases/latest',
            ),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw StateError('GitHub returned ${response.statusCode}');
      }
      final candidate = AppRelease.parse(
        jsonDecode(response.body) as Map<String, dynamic>,
        ios: isIOS,
      );
      if (candidate == null) {
        status = 'No compatible release attached yet';
      } else if (!AppRelease.isNewer(candidate.version, currentVersion)) {
        status = 'You’re up to date';
      } else {
        if (release?.version != candidate.version) downloaded = null;
        release = candidate;
        final existing = await _packageFile(candidate);
        if (await _validPackage(existing, candidate.size)) {
          downloaded = existing;
          await _rememberPackage(candidate);
        }
        status = downloaded != null
            ? 'Version ${candidate.version} ready to install'
            : 'Version ${candidate.version} available';
      }
    } catch (_) {
      status = downloaded != null
          ? 'Downloaded update ready. GitHub is unavailable.'
          : 'Could not check GitHub. Try again.';
    } finally {
      busy = false;
      notifyListeners();
    }
    if (automatic && autoDownload && release != null && downloaded == null) {
      try {
        final connections = await Connectivity().checkConnectivity();
        if (connections.contains(ConnectivityResult.wifi)) {
          await download(wifiOnly: true);
        }
      } catch (_) {
        // Connectivity lookup failure must not break app startup.
      }
    }
  }

  Future<void> download({bool wifiOnly = false}) async {
    final candidate = release;
    if (busy || candidate == null) return;
    busy = true;
    progress = 0;
    status = 'Downloading update…';
    final client = _clientFactory();
    _downloadClient = client;
    _cancellation = Completer<void>();
    notifyListeners();
    StreamSubscription<List<ConnectivityResult>>? connection;
    if (wifiOnly) {
      connection = Connectivity().onConnectivityChanged.listen((results) {
        if (!results.contains(ConnectivityResult.wifi)) cancelDownload();
      });
    }
    File? partial;
    IOSink? sink;
    try {
      final root = await _supportDirectory();
      final directory = await Directory(
        '${root.path}/Updates',
      ).create(recursive: true);
      final extension = isIOS ? 'ipa' : 'apk';
      final target = File(
        '${directory.path}/monolith-${candidate.version}.$extension',
      );
      if (candidate.size > 0 &&
          await target.exists() &&
          await target.length() == candidate.size) {
        final handle = await target.open();
        final bytes = await handle.read(4);
        await handle.close();
        if (bytes.length == 4 &&
            bytes[0] == 0x50 &&
            bytes[1] == 0x4b &&
            bytes[2] == 3 &&
            bytes[3] == 4) {
          downloaded = target;
          status = 'Update ready to install';
          progress = null;
          await _rememberPackage(candidate);
          return;
        }
      }
      partial = File('${target.path}.part');
      final response = await _wait(
        client.send(http.Request('GET', candidate.url)),
        const Duration(seconds: 20),
      );
      if (response.statusCode != 200) throw StateError('Download failed');
      sink = partial.openWrite();
      var received = 0;
      var buffered = 0;
      var lastNotice = DateTime.now();
      final iterator = StreamIterator(response.stream);
      try {
        while (await _wait(iterator.moveNext(), const Duration(seconds: 30))) {
          final chunk = iterator.current;
          received += chunk.length;
          if (received > 512 * 1024 * 1024) {
            throw StateError('Update too large');
          }
          sink.add(chunk);
          buffered += chunk.length;
          if (buffered >= 256 * 1024) {
            await sink.flush();
            buffered = 0;
          }
          if (DateTime.now().difference(lastNotice).inMilliseconds > 250) {
            progress = candidate.size > 0
                ? (received / candidate.size).clamp(0, 1)
                : null;
            notifyListeners();
            lastNotice = DateTime.now();
          }
        }
      } finally {
        unawaited(iterator.cancel().catchError((Object _) {}));
      }
      if (_cancellation!.isCompleted) {
        throw StateError('Update download cancelled');
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (received == 0 || (candidate.size > 0 && received != candidate.size)) {
        throw StateError('Incomplete download');
      }
      final header = await partial.open();
      final signature = await header.read(4);
      await header.close();
      if (signature.length != 4 ||
          signature[0] != 0x50 ||
          signature[1] != 0x4b ||
          signature[2] != 3 ||
          signature[3] != 4) {
        throw StateError('Invalid update archive');
      }
      downloaded = await partial.rename(target.path);
      await _rememberPackage(candidate);
      status = 'Update ready to install';
      progress = null;
    } catch (_) {
      status = _cancellation!.isCompleted
          ? 'Update download cancelled.'
          : 'Download interrupted. Tap Download to retry.';
      progress = null;
      await sink?.close();
      if (partial != null && await partial.exists()) await partial.delete();
    } finally {
      await connection?.cancel();
      client.close();
      _downloadClient = null;
      _cancellation = null;
      progress = null;
      busy = false;
      notifyListeners();
    }
  }
}
