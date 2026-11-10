import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Ephemeral P-256 identity for one Receive session, matching the desktop's
/// rcgen self-signed certificate. dart:io can serve TLS from PEM bytes but
/// cannot mint a key or certificate, so this file builds both: ECDSA over
/// P-256 with BigInt arithmetic and a minimal DER X.509 v3 encoder. The key
/// never leaves memory and is discarded when the session closes.
///
/// Side channels are out of scope: the key lives for at most five minutes and
/// signs exactly one message (its own certificate). BoringSSL signs the TLS
/// handshake itself with this key once it is loaded into a SecurityContext.
class NearbyCertificate {
  NearbyCertificate._(this.der, this.privateKeyPem, this.fingerprint);

  /// DER-encoded certificate; SHA-256 of these bytes is the pinned fingerprint.
  final Uint8List der;
  final Uint8List privateKeyPem;
  final String fingerprint;

  Uint8List get certificatePem => _pem('CERTIFICATE', der);

  /// Generic three-word alias derived from the certificate, identical to the
  /// desktop `session_name` so both platforms label sessions the same way.
  String get alias => nearbySessionName(der);

  SecurityContext serverContext() => SecurityContext(withTrustedRoots: false)
    ..minimumTlsProtocolVersion = TlsProtocolVersion.tls1_3
    ..useCertificateChainBytes(certificatePem)
    ..usePrivateKeyBytes(privateKeyPem);

  static NearbyCertificate generate({Random? random, DateTime? now}) {
    final rng = random ?? Random.secure();
    final d = _randomScalar(rng);
    final q = _P256.multiply(_P256.g, d)!;
    final publicPoint = Uint8List.fromList([
      0x04,
      ..._fixed(q.x, 32),
      ..._fixed(q.y, 32),
    ]);
    final serial = Uint8List.fromList(
      List<int>.generate(16, (_) => rng.nextInt(256)),
    );
    serial[0] = (serial[0] & 0x7f) | 0x01; // positive and non-zero
    final at = (now ?? DateTime.now()).toUtc();
    final name = _seq([
      _set([
        _seq([_oid(_oidCommonName), _tlv(0x0c, utf8.encode(_host))]),
      ]),
    ]);
    final tbs = _seq([
      _tlv(0xa0, _integer(BigInt.two)),
      _integerBytes(serial),
      _seq([_oid(_oidEcdsaSha256)]),
      name,
      _seq([
        _utcTime(at.subtract(const Duration(days: 1))),
        _utcTime(at.add(const Duration(days: 2))),
      ]),
      name,
      _seq([
        _seq([_oid(_oidEcPublicKey), _oid(_oidPrime256v1)]),
        _bitString(publicPoint),
      ]),
      _tlv(
        0xa3,
        _seq([
          _seq([
            _oid(_oidSubjectAltName),
            _tlv(
              0x04,
              _seq([_tlv(0x82, ascii.encode(_host))]),
            ),
          ]),
        ]),
      ),
    ]);
    final signature = _P256.sign(tbs, d, rng);
    final der = _seq([
      tbs,
      _seq([_oid(_oidEcdsaSha256)]),
      _bitString(signature),
    ]);
    final sec1 = _seq([
      _integer(BigInt.one),
      _tlv(0x04, _fixed(d, 32)),
      _tlv(0xa1, _bitString(publicPoint)),
    ]);
    final pkcs8 = _seq([
      _integer(BigInt.zero),
      _seq([_oid(_oidEcPublicKey), _oid(_oidPrime256v1)]),
      _tlv(0x04, sec1),
    ]);
    return NearbyCertificate._(
      der,
      _pem('PRIVATE KEY', pkcs8),
      nearbyFingerprint(der),
    );
  }

  static const _host = 'monolith.local';

  static BigInt _randomScalar(Random rng) {
    while (true) {
      final value = _toInt(List<int>.generate(32, (_) => rng.nextInt(256)));
      if (value > BigInt.zero && value < _P256.n) return value;
    }
  }
}

String nearbyFingerprint(List<int> der) => sha256.convert(der).toString();

String nearbySessionName(List<int> der) {
  const first = [
    'Quiet', 'Bright', 'Gentle', 'Calm', 'Swift', 'Soft', 'Warm', 'Clear', //
    'Little', 'Sunny', 'Silver', 'Golden', 'Happy', 'Mellow', 'Fresh', 'Cosy',
  ];
  const second = [
    'Coral', 'Amber', 'Jade', 'Blue', 'Ivory', 'Ruby', 'Pearl', 'Indigo', //
    'Rose', 'Mint', 'Violet', 'Copper', 'Teal', 'Olive', 'Aqua', 'Lilac',
  ];
  const third = [
    'Cedar', 'Piano', 'Falcon', 'Comet', 'Harp', 'Willow', 'Finch', 'Maple', //
    'Echo', 'Orchid', 'Robin', 'Ocean', 'Sparrow', 'Melody', 'River', 'Moon',
  ];
  final h = sha256.convert(der).bytes;
  return '${first[h[0] & 15]} ${second[h[1] & 15]} ${third[h[2] & 15]}';
}

/// Verifies an ECDSA P-256/SHA-256 signature. Used by tests to prove the
/// generated certificate is correctly self-signed.
bool nearbyVerifyP256(
  List<int> message,
  List<int> derSignature,
  List<int> publicPoint,
) {
  try {
    final (r, s) = _parseSignature(derSignature);
    if (publicPoint.length != 65 || publicPoint[0] != 4) return false;
    final q = _Point(
      _toInt(publicPoint.sublist(1, 33)),
      _toInt(publicPoint.sublist(33)),
    );
    final n = _P256.n;
    if (r <= BigInt.zero || r >= n || s <= BigInt.zero || s >= n) return false;
    final e = _toInt(sha256.convert(message).bytes);
    final w = s.modInverse(n);
    final x = _P256.add(
      _P256.multiply(_P256.g, (e * w) % n),
      _P256.multiply(q, (r * w) % n),
    );
    return x != null && x.x % n == r;
  } catch (_) {
    return false;
  }
}

(BigInt, BigInt) _parseSignature(List<int> der) {
  if (der[0] != 0x30) throw const FormatException('signature');
  var i = 2;
  BigInt readInt() {
    if (der[i] != 0x02) throw const FormatException('signature');
    final len = der[i + 1];
    final value = _toInt(der.sublist(i + 2, i + 2 + len));
    i += 2 + len;
    return value;
  }

  return (readInt(), readInt());
}

class _Point {
  const _Point(this.x, this.y);
  final BigInt x;
  final BigInt y;
}

abstract final class _P256 {
  static final p = BigInt.parse(
    'ffffffff00000001000000000000000000000000ffffffffffffffffffffffff',
    radix: 16,
  );
  static final n = BigInt.parse(
    'ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551',
    radix: 16,
  );
  static final a = p - BigInt.from(3);
  static final g = _Point(
    BigInt.parse(
      '6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296',
      radix: 16,
    ),
    BigInt.parse(
      '4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5',
      radix: 16,
    ),
  );

  static _Point? add(_Point? l, _Point? r) {
    if (l == null) return r;
    if (r == null) return l;
    BigInt slope;
    if (l.x == r.x) {
      if ((l.y + r.y) % p == BigInt.zero) return null;
      slope =
          (BigInt.from(3) * l.x * l.x + a) * (BigInt.two * l.y).modInverse(p);
    } else {
      slope = (r.y - l.y) * ((r.x - l.x) % p).modInverse(p);
    }
    slope %= p;
    final x = (slope * slope - l.x - r.x) % p;
    return _Point(x, (slope * (l.x - x) - l.y) % p);
  }

  static _Point? multiply(_Point? point, BigInt k) {
    _Point? result;
    var addend = point;
    for (var i = 0; i < k.bitLength; i++) {
      if ((k >> i).isOdd) result = add(result, addend);
      addend = add(addend, addend);
    }
    return result;
  }

  static Uint8List sign(List<int> message, BigInt d, Random rng) {
    final e = _toInt(sha256.convert(message).bytes);
    while (true) {
      final k = NearbyCertificate._randomScalar(rng);
      final r = multiply(g, k)!.x % n;
      if (r == BigInt.zero) continue;
      final s = (k.modInverse(n) * (e + r * d)) % n;
      if (s == BigInt.zero) continue;
      return _seq([_integer(r), _integer(s)]);
    }
  }
}

// ── Minimal DER encoder ────────────────────────────────────────────────────

const _oidEcPublicKey = [1, 2, 840, 10045, 2, 1];
const _oidPrime256v1 = [1, 2, 840, 10045, 3, 1, 7];
const _oidEcdsaSha256 = [1, 2, 840, 10045, 4, 3, 2];
const _oidCommonName = [2, 5, 4, 3];
const _oidSubjectAltName = [2, 5, 29, 17];

BigInt _toInt(List<int> bytes) =>
    bytes.fold(BigInt.zero, (v, b) => (v << 8) | BigInt.from(b));

Uint8List _fixed(BigInt value, int length) {
  final out = Uint8List(length);
  var v = value;
  for (var i = length - 1; i >= 0; i--) {
    out[i] = (v & BigInt.from(0xff)).toInt();
    v >>= 8;
  }
  return out;
}

Uint8List _tlv(int tag, List<int> body) {
  final length = body.length;
  final header = <int>[tag];
  if (length < 0x80) {
    header.add(length);
  } else {
    final bytes = <int>[];
    for (var v = length; v > 0; v >>= 8) {
      bytes.insert(0, v & 0xff);
    }
    header
      ..add(0x80 | bytes.length)
      ..addAll(bytes);
  }
  return Uint8List.fromList([...header, ...body]);
}

Uint8List _seq(List<List<int>> items) =>
    _tlv(0x30, [for (final item in items) ...item]);

Uint8List _set(List<List<int>> items) =>
    _tlv(0x31, [for (final item in items) ...item]);

Uint8List _integer(BigInt value) {
  final bytes = value == BigInt.zero
      ? Uint8List(1)
      : _fixed(value, (value.bitLength + 7) ~/ 8);
  return _integerBytes(bytes);
}

Uint8List _integerBytes(List<int> unsigned) {
  var start = 0;
  while (start < unsigned.length - 1 && unsigned[start] == 0) {
    start++;
  }
  final body = unsigned.sublist(start);
  return _tlv(0x02, body[0] & 0x80 != 0 ? [0, ...body] : body);
}

Uint8List _bitString(List<int> bytes) => _tlv(0x03, [0, ...bytes]);

Uint8List _oid(List<int> parts) {
  final body = <int>[40 * parts[0] + parts[1]];
  for (final part in parts.skip(2)) {
    final chunk = <int>[part & 0x7f];
    for (var v = part >> 7; v > 0; v >>= 7) {
      chunk.insert(0, 0x80 | (v & 0x7f));
    }
    body.addAll(chunk);
  }
  return _tlv(0x06, body);
}

Uint8List _utcTime(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return _tlv(
    0x17,
    ascii.encode(
      '${two(t.year % 100)}${two(t.month)}${two(t.day)}'
      '${two(t.hour)}${two(t.minute)}${two(t.second)}Z',
    ),
  );
}

Uint8List _pem(String label, List<int> der) {
  final encoded = base64.encode(der);
  final lines = [
    for (var i = 0; i < encoded.length; i += 64)
      encoded.substring(i, min(i + 64, encoded.length)),
  ];
  return ascii.encode(
    '-----BEGIN $label-----\n${lines.join('\n')}\n-----END $label-----\n',
  );
}
