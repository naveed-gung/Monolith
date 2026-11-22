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

/// Optional cover-art sidecar that may follow the audio bytes (protocol v1
/// artwork extension, docs/nearby-music.md). Same cap as the desktop cover
/// decoder; older peers ignore the extra offer fields and never ask for it.
const nearbyMaxArtworkBytes = 8 * 1024 * 1024;
const nearbyArtworkExtensions = <String>{'jpg', 'png', 'webp'};

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

bool nearbyValidFingerprint(String value) => _isHex64(value);

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

bool _isHex64(String value) =>
    value.length == 64 &&
    value.codeUnits.every(
      (c) =>
          (c >= 0x30 && c <= 0x39) ||
          (c >= 0x61 && c <= 0x66) ||
          (c >= 0x41 && c <= 0x46),
    );

/// Sniffs JPEG / PNG / WebP magic bytes and returns the sidecar extension, or
/// null when [bytes] is not a supported image. The receiver never trusts the
/// advertised extension alone.
String? nearbyArtworkKind(List<int> bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff) {
    return 'jpg';
  }
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47) {
    return 'png';
  }
  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
      String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
    return 'webp';
  }
  return null;
}

/// A validated one-song offer, identical to the desktop `Offer`, plus the
/// optional artwork sidecar description (`artworkSize == 0` means none).
class NearbyOffer {
  const NearbyOffer({
    required this.name,
    required this.title,
    required this.size,
    required this.sha256,
    this.artworkSize = 0,
    this.artworkSha256 = '',
    this.artworkExt = '',
  });

  final String name;
  final String title;
  final int size;
  final String sha256;
  final int artworkSize;
  final String artworkSha256;
  final String artworkExt;

  bool get hasArtwork => artworkSize > 0;

  void validate() {
    if (!nearbyValidName(name) ||
        !_cleanText(title, 480) ||
        size <= 0 ||
        size > nearbyMaxSongBytes ||
        !_isHex64(sha256)) {
      throw const FormatException(
        'Invalid song offer. Only audio files up to 100 MB are accepted.',
      );
    }
    if (hasArtwork &&
        (artworkSize > nearbyMaxArtworkBytes ||
            !_isHex64(artworkSha256) ||
            !nearbyArtworkExtensions.contains(artworkExt))) {
      throw const FormatException('Invalid artwork in song offer.');
    }
  }

  Map<String, Object?> toJson() => {
    'type': 'offer',
    'name': name,
    'title': title,
    'size': size,
    'sha256': sha256,
    if (hasArtwork) ...{
      'artwork_size': artworkSize,
      'artwork_sha256': artworkSha256,
      'artwork_ext': artworkExt,
    },
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
    // Artwork is optional: a malformed description is dropped (the receiver
    // then simply never asks for it) instead of refusing the song.
    final rawArtSize = value['artwork_size'];
    final artSha = value['artwork_sha256'];
    final artExt = value['artwork_ext'];
    if (rawArtSize is int &&
        rawArtSize > 0 &&
        rawArtSize <= nearbyMaxArtworkBytes &&
        artSha is String &&
        _isHex64(artSha) &&
        artExt is String &&
        nearbyArtworkExtensions.contains(artExt.toLowerCase())) {
      return NearbyOffer(
        name: offer.name,
        title: offer.title,
        size: offer.size,
        sha256: offer.sha256,
        artworkSize: rawArtSize,
        artworkSha256: artSha.toLowerCase(),
        artworkExt: artExt.toLowerCase(),
      );
    }
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
