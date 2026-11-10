import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Monolith Music wire contract v1 — a byte-for-byte port of the desktop
/// `src/nearby.rs` / `src/lan.rs` rules (docs/nearby-music.md). One explicitly
/// accepted song per encrypted connection.
const nearbyServiceUuid = 'e8793c34-7c2e-49ad-88c2-16c9a0762c91';
const nearbyMaxSongBytes = 100000000;
const nearbyMaxControlBytes = 16 * 1024;
const nearbyDiscoveryPort = 45881;
const nearbyMaxPeers = 32;

/// Extensions the desktop receiver publishes (nearby-music.md "Supported
/// extensions match the existing importer"). Kept as the wire set for both
/// directions so mobile stays byte-for-byte compatible with desktop.
const nearbyWireExtensions = <String>{
  'mp3',
  'm4a',
  'aac',
  'flac',
  'wav',
  'ogg',
  'aif',
  'aiff',
};

const nearbyHello = <String, Object?>{
  'type': 'hello',
  'app': 'monolith-music',
  'version': 1,
};

/// Hello must match exactly: unsupported versions/apps/extra fields are
/// rejected, like `value != hello()` in nearby.rs.
bool nearbyCheckHello(Object? value) {
  if (value is! Map) return false;
  if (value.length != nearbyHello.length) return false;
  for (final entry in nearbyHello.entries) {
    if (value[entry.key] != entry.value) return false;
  }
  return true;
}

bool _cleanText(String value, int utf8Limit) =>
    value.isNotEmpty &&
    utf8.encode(value).length <= utf8Limit &&
    !value.codeUnits.any(_isControl);

bool _isControl(int unit) =>
    unit < 0x20 || (unit >= 0x7f && unit <= 0x9f);

bool _supportedExtension(String name) {
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return false;
  return nearbyWireExtensions.contains(name.substring(dot + 1).toLowerCase());
}

/// Port of `valid_name` in nearby.rs: portable audio basename, ≤180 UTF-8
/// bytes, no separators/control characters, no leading dot, no trailing
/// space/dot, no reserved Windows device stem, and a supported extension.
bool nearbyValidName(String name) {
  const forbidden = ['/', '\\', ':', '*', '?', '"', '<', '>', '|'];
  final stem = name.split('.').first.toUpperCase();
  return _cleanText(name, 180) &&
      !forbidden.any(name.contains) &&
      !name.startsWith('.') &&
      !name.endsWith('.') &&
      !name.endsWith(' ') &&
      !['CON', 'PRN', 'AUX', 'NUL'].contains(stem) &&
      !(stem.length == 4 &&
          (stem.startsWith('COM') || stem.startsWith('LPT')) &&
          _isAsciiDigit(stem.codeUnitAt(3))) &&
      _supportedExtension(name);
}

bool _isAsciiDigit(int unit) => unit >= 0x30 && unit <= 0x39;

bool nearbyValidFingerprint(String value) =>
    value.length == 64 &&
    value.codeUnits.every(
      (c) =>
          (c >= 0x30 && c <= 0x39) ||
          (c >= 0x61 && c <= 0x66) ||
          (c >= 0x41 && c <= 0x46),
    );

/// IPv4 link-local/loopback/private check, matching `local()` in lan.rs. The
/// sender derives the IP from the datagram source and rejects anything else.
bool nearbyLocalAddress(InternetAddress address) {
  if (address.type != InternetAddressType.IPv4) return false;
  final b = address.rawAddress;
  return b[0] == 127 ||
      b[0] == 10 ||
      (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
      (b[0] == 192 && b[1] == 168) ||
      (b[0] == 169 && b[1] == 254);
}

String _lowerHex(List<int> bytes) {
  const digits = '0123456789abcdef';
  final out = StringBuffer();
  for (final b in bytes) {
    out
      ..writeCharCode(digits.codeUnitAt(b >> 4))
      ..writeCharCode(digits.codeUnitAt(b & 15));
  }
  return out.toString();
}

String nearbyHex(List<int> bytes) => _lowerHex(bytes);

/// A validated one-song offer, identical to the desktop `Offer`.
class NearbyOffer {
  const NearbyOffer({
    required this.name,
    required this.title,
    required this.size,
    required this.sha256,
  });

  final String name;
  final String title;
  final int size;
  final String sha256;

  void validate() {
    if (!nearbyValidName(name) ||
        !_cleanText(title, 480) ||
        size <= 0 ||
        size > nearbyMaxSongBytes ||
        sha256.length != 64 ||
        !sha256.codeUnits.every(
          (c) =>
              (c >= 0x30 && c <= 0x39) ||
              (c >= 0x61 && c <= 0x66) ||
              (c >= 0x41 && c <= 0x46),
        )) {
      throw const FormatException(
        'Invalid song offer. Only audio files up to 100 MB are accepted.',
      );
    }
  }

  Map<String, Object?> toJson() => {
    'type': 'offer',
    'name': name,
    'title': title,
    'size': size,
    'sha256': sha256,
  };

  static NearbyOffer parse(Object? value) {
    if (value is! Map || value['type'] != 'offer') {
      throw const FormatException('Expected a song offer.');
    }
    // size must be an unsigned integer like serde_json's as_u64 — floats and
    // negatives fall to 0 and fail validation.
    final rawSize = value['size'];
    final offer = NearbyOffer(
      name: value['name'] as String? ?? '',
      title: value['title'] as String? ?? '',
      size: rawSize is int && rawSize > 0 ? rawSize : 0,
      sha256: (value['sha256'] as String? ?? '').toLowerCase(),
    );
    offer.validate();
    return offer;
  }
}

/// 4-byte unsigned big-endian UTF-8 JSON byte length, then exactly that many
/// JSON bytes. Length must be 1–16,384 (nearby.rs control_write/control_read).
Uint8List nearbyEncodeControl(Map<String, Object?> value) {
  final data = utf8.encode(jsonEncode(value));
  if (data.isEmpty || data.length > nearbyMaxControlBytes) {
    throw const FormatException('Sharing message exceeds its limit.');
  }
  final out = Uint8List(4 + data.length);
  out.buffer.asByteData().setUint32(0, data.length);
  out.setRange(4, out.length, data);
  return out;
}

/// Decodes the body of a control record once the exact byte count is known.
Object? nearbyDecodeControl(Uint8List body) {
  if (body.isEmpty || body.length > nearbyMaxControlBytes) {
    throw const FormatException('Invalid sharing message length.');
  }
  return jsonDecode(utf8.decode(body));
}
