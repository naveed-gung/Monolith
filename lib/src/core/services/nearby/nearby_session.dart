import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'nearby_certificate.dart';
import 'nearby_channel.dart';
import 'nearby_discovery.dart';
import 'nearby_wire.dart';

/// TLS 1.3 transport for the wire protocol. Discovery supplies the selected
/// endpoint's certificate fingerprint; the client pins it — there is no
/// accept-all path. Handshake signature verification is performed by the TLS
/// stack itself.
SecurityContext _clientContext() =>
    SecurityContext(withTrustedRoots: false)
      ..minimumTlsProtocolVersion = TlsProtocolVersion.tls1_3;

/// Connects to [peer] with TLS 1.3 only, accepting the self-signed
/// certificate solely when its DER SHA-256 equals the fingerprint carried by
/// discovery (lan.rs `Pinned` verifier). A changed certificate fails the
/// connection — refresh nearby devices and try again.
Future<NearbyChannel> nearbyConnect(
  NearbyPeer peer,
  NearbyCancel cancel, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  if (!nearbyLocalAddress(peer.address) ||
      peer.port <= 0 ||
      !nearbyValidFingerprint(peer.fingerprint)) {
    throw const SocketException('Choose a device on your local network.');
  }
  final expected = peer.fingerprint.toLowerCase();
  SecureSocket socket;
  try {
    socket = await SecureSocket.connect(
      peer.address,
      peer.port,
      context: _clientContext(),
      timeout: timeout,
      onBadCertificate: (certificate) =>
          sha256.convert(certificate.der).toString() == expected,
    ).timeout(timeout);
  } on HandshakeException {
    throw const SocketException(
      'Device certificate changed. Refresh nearby devices and try again.',
    );
  }
  return NearbyChannel(socket, cancel: cancel);
}

/// The five-minute foreground Receive session: an ephemeral TLS listener plus
/// a discovery responder, active only while the Receive UI is open (lan.rs
/// `Listener`). One worker serializes offers, so accepted connections run one
/// at a time; Close/Cancel stops discovery and drops receiving sockets.
class NearbyReceiver {
  NearbyReceiver._(
    this.certificate,
    this._server,
    this._responder,
    this.cancel,
  );

  final NearbyCertificate certificate;
  final SecureServerSocket _server;
  final NearbyDiscoveryResponder? _responder;
  final NearbyCancel cancel;

  String get alias => certificate.alias;
  String get fingerprint => certificate.fingerprint;
  int get port => _server.port;

  final List<NearbyChannel> _active = [];
  StreamIterator<SecureSocket>? _iterator;
  Future<bool>? _pendingNext;
  bool _closed = false;

  /// Binds the TLS listener and starts answering discovery. [host] stays
  /// `anyIPv4` on device; tests pass `loopbackIPv4`.
  static Future<NearbyReceiver> start({
    required NearbyCancel cancel,
    InternetAddress? host,
    bool advertise = true,
  }) async {
    final certificate = NearbyCertificate.generate();
    final server = await SecureServerSocket.bind(
      host ?? InternetAddress.anyIPv4,
      0,
      certificate.serverContext(),
    );
    NearbyDiscoveryResponder? responder;
    if (advertise) {
      responder = await NearbyDiscoveryResponder.start(
        port: server.port,
        alias: certificate.alias,
        fingerprint: certificate.fingerprint,
      );
    }
    return NearbyReceiver._(certificate, server, responder, cancel);
  }

  /// Accepts the next connection from a local IPv4 peer as a channel. Returns
  /// null once cancelled or closed. Cancellation is polled every 200 ms, like
  /// the desktop's socket cadence.
  Future<NearbyChannel?> accept() async {
    _iterator ??= StreamIterator(_server);
    while (!_closed && !cancel.cancelled) {
      // Keep one pending moveNext across polls so a connection arriving
      // during a timer tick is never consumed by a stale subscription.
      _pendingNext ??= _iterator!.moveNext();
      final result = await Future.any<Object?>([
        _pendingNext!,
        cancel.onCancel,
        Future.delayed(const Duration(milliseconds: 200)),
      ]);
      if (result is! bool) continue;
      _pendingNext = null;
      if (!result) return null; // listener closed
      final socket = _iterator!.current;
      if (!nearbyLocalAddress(socket.remoteAddress)) {
        socket.destroy();
        continue;
      }
      final channel = NearbyChannel(socket, cancel: cancel);
      _active.add(channel);
      return channel;
    }
    return null;
  }

  void release(NearbyChannel channel) {
    _active.remove(channel);
  }

  /// Close/Cancel: stop discovery, drop the listener and abort active sockets.
  Future<void> close() async {
    _closed = true;
    cancel.cancel();
    for (final channel in List.of(_active)) {
      channel.destroy();
    }
    _active.clear();
    await _responder?.close();
    await _server.close();
  }
}
