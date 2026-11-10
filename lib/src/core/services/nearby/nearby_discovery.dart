import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'nearby_channel.dart';
import 'nearby_wire.dart';

/// Opt-in UDP discovery on port 45881, matching `lan.rs` exactly. The query is
/// `{"app":"monolith-music","version":1,"type":"discover","nonce":"<32 hex>"}`;
/// a receiving session answers its source with `available` carrying its TCP
/// port, generated session alias and SHA-256 DER certificate fingerprint.
/// Discovery is unauthenticated — the fingerprint pins the TLS endpoint and
/// explicit recipient consent protects each song.
class NearbyPeer {
  const NearbyPeer({
    required this.name,
    required this.address,
    required this.port,
    required this.fingerprint,
  });

  /// `alias · ipv4` picker label.
  final String name;
  final InternetAddress address;
  final int port;
  final String fingerprint;

  /// Stable device ID across automatic list refreshes: a peer that disappears
  /// cannot reroute Send because the selected peer's address+fingerprint is
  /// fixed at tap time.
  String get id => '${address.address}:$port:$fingerprint';
}

/// Parses an `available` reply, port of `parse_peer` in lan.rs: local source
/// IP, exact app/version/type, echoed nonce, port 1–65535, a 64-hex
/// fingerprint and a bounded control-free alias.
NearbyPeer? nearbyParsePeer(
  Object? value,
  InternetAddress source,
  String nonce,
) {
  if (value is! Map ||
      !nearbyLocalAddress(source) ||
      value['app'] != 'monolith-music' ||
      value['version'] != 1 ||
      value['type'] != 'available' ||
      value['nonce'] != nonce) {
    return null;
  }
  final rawPort = value['port'];
  final port = rawPort is int ? rawPort : 0;
  if (port <= 0 || port > 65535) return null;
  final fingerprint = value['fingerprint'] as String?;
  if (fingerprint == null || !nearbyValidFingerprint(fingerprint)) return null;
  final alias = value['alias'] as String?;
  if (alias == null ||
      alias.trim().isEmpty ||
      utf8.encode(alias).length > 64 ||
      alias.codeUnits.any((c) => c < 0x20 || (c >= 0x7f && c <= 0x9f))) {
    return null;
  }
  return NearbyPeer(
    name: '${alias.trim()} · ${source.address}',
    address: source,
    port: port,
    fingerprint: fingerprint.toLowerCase(),
  );
}

/// One 2-second broadcast scan (lan.rs `discover`). Cancellation is polled on
/// every datagram and timer tick.
Future<List<NearbyPeer>> nearbyDiscover({
  required NearbyCancel cancel,
  InternetAddress? broadcastAddress,
  Duration window = const Duration(seconds: 2),
  int maxPeers = nearbyMaxPeers,
}) async {
  final socket = await RawDatagramSocket.bind(
    InternetAddress.anyIPv4,
    0,
    reuseAddress: true,
  );
  try {
    socket.broadcastEnabled = true;
    final nonceBytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final nonce = nearbyHex(nonceBytes);
    final query = utf8.encode(
      jsonEncode({
        'app': 'monolith-music',
        'version': 1,
        'type': 'discover',
        'nonce': nonce,
      }),
    );
    socket.send(
      query,
      broadcastAddress ?? InternetAddress('255.255.255.255'),
      nearbyDiscoveryPort,
    );
    final peers = <NearbyPeer>[];
    final seen = <String>{};
    final done = Completer<void>();
    // Datagrams only queue while the socket is listened to; the read event is
    // drained with receive() like the desktop's non-blocking poll.
    final subscription = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      Datagram? datagram;
      while ((datagram = socket.receive()) != null) {
        final source = datagram!.address;
        if (!nearbyLocalAddress(source) || datagram.data.length > 2048) {
          continue;
        }
        Object? decoded;
        try {
          decoded = jsonDecode(utf8.decode(datagram.data));
        } catch (_) {
          continue;
        }
        final peer = nearbyParsePeer(decoded, source, nonce);
        if (peer != null && seen.add(peer.id)) {
          peers.add(peer);
          if (peers.length >= maxPeers && !done.isCompleted) {
            done.complete();
            return;
          }
        }
      }
    });
    try {
      await Future.any([
        done.future,
        Future.delayed(window),
        cancel.onCancel,
      ]);
    } finally {
      await subscription.cancel();
    }
    return peers;
  } finally {
    socket.close();
  }
}

/// Answers `discover` datagrams with the listening session's `available`
/// reply. Lives only while a Receive session is open (lan.rs `Listener`).
class NearbyDiscoveryResponder {
  NearbyDiscoveryResponder._(this._socket, this._subscription);

  final RawDatagramSocket _socket;
  final StreamSubscription<RawSocketEvent> _subscription;

  static Future<NearbyDiscoveryResponder> start({
    required int port,
    required String alias,
    required String fingerprint,
  }) async {
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      nearbyDiscoveryPort,
      reuseAddress: true,
    );
    final subscription = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      Datagram? datagram;
      // Bound work per event even if a peer floods discovery packets.
      var processed = 0;
      while ((datagram = socket.receive()) != null && processed++ < 8) {
        final source = datagram!.address;
        if (!nearbyLocalAddress(source) || datagram.data.length > 2048) {
          continue;
        }
        Object? decoded;
        try {
          decoded = jsonDecode(utf8.decode(datagram.data));
        } catch (_) {
          continue;
        }
        if (decoded is! Map) continue;
        final nonce = decoded['nonce'];
        if (decoded['app'] == 'monolith-music' &&
            decoded['version'] == 1 &&
            decoded['type'] == 'discover' &&
            nonce is String &&
            nonce.length == 32 &&
            nonce.codeUnits.every(
              (c) =>
                  (c >= 0x30 && c <= 0x39) ||
                  (c >= 0x61 && c <= 0x66) ||
                  (c >= 0x41 && c <= 0x46),
            )) {
          final reply = utf8.encode(
            jsonEncode({
              'app': 'monolith-music',
              'version': 1,
              'type': 'available',
              'nonce': nonce,
              'port': port,
              'alias': alias,
              'fingerprint': fingerprint,
            }),
          );
          socket.send(reply, source, datagram.port);
        }
      }
    });
    return NearbyDiscoveryResponder._(socket, subscription);
  }

  Future<void> close() async {
    await _subscription.cancel();
    _socket.close();
  }
}
