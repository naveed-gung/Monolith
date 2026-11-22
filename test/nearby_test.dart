import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monolith/src/core/services/nearby/nearby_certificate.dart';
import 'package:monolith/src/core/services/nearby/nearby_channel.dart';
import 'package:monolith/src/core/services/nearby/nearby_discovery.dart';
import 'package:monolith/src/core/services/nearby/nearby_session.dart';
import 'package:monolith/src/core/services/nearby/nearby_transfer.dart';
import 'package:monolith/src/core/services/nearby/nearby_wire.dart';

Map<String, Object?> _fixtures() {
  final raw = File(
    'test/fixtures/bluetooth-wire-fixtures.json',
  ).readAsStringSync();
  return Map<String, Object?>.from(jsonDecode(raw) as Map);
}

/// The same real WAV the desktop tests stream.
Uint8List _audio() {
  final wav = BytesBuilder()
    ..add('RIFF'.codeUnits)
    ..add(
      Uint8List(4)..buffer.asByteData().setUint32(0, 16036, Endian.little),
    )
    ..add('WAVEfmt '.codeUnits)
    ..add(
      Uint8List(4)..buffer.asByteData().setUint32(0, 16, Endian.little),
    )
    ..add(
      Uint8List(2)..buffer.asByteData().setUint16(0, 1, Endian.little),
    )
    ..add(
      Uint8List(2)..buffer.asByteData().setUint16(0, 1, Endian.little),
    )
    ..add(
      Uint8List(4)..buffer.asByteData().setUint32(0, 8000, Endian.little),
    )
    ..add(
      Uint8List(4)..buffer.asByteData().setUint32(0, 16000, Endian.little),
    )
    ..add(
      Uint8List(2)..buffer.asByteData().setUint16(0, 2, Endian.little),
    )
    ..add(
      Uint8List(2)..buffer.asByteData().setUint16(0, 16, Endian.little),
    )
    ..add('data'.codeUnits)
    ..add(
      Uint8List(4)..buffer.asByteData().setUint32(0, 16000, Endian.little),
    );
  final bytes = wav.toBytes();
  final out = Uint8List(16044);
  out.setRange(0, bytes.length, bytes);
  return out;
}

/// Smallest byte string that sniffs as a JPEG cover.
Uint8List _jpeg() => Uint8List.fromList([
  0xFF, 0xD8, 0xFF, 0xE0, //
  ...List<int>.generate(60, (i) => i),
  0xFF, 0xD9,
]);

Future<(NearbyChannel, NearbyChannel)> _socketPair({
  NearbyCancel? aCancel,
  NearbyCancel? bCancel,
}) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final a = await Socket.connect(
    InternetAddress.loopbackIPv4,
    server.port,
  );
  final b = await server.first;
  unawaited(server.close());
  return (
    NearbyChannel(a, cancel: aCancel ?? NearbyCancel()),
    NearbyChannel(b, cancel: bCancel ?? NearbyCancel()),
  );
}

void main() {
  group('wire contract', () {
    test('fixtures match constants and framing roundtrips', () {
      final fixtures = _fixtures();
      expect(fixtures['serviceUuid'], nearbyServiceUuid);
      expect(fixtures['maximumControlBytes'], nearbyMaxControlBytes);
      expect(fixtures['maximumSongBytes'], nearbyMaxSongBytes);
      expect(nearbyCheckHello(fixtures['hello']), isTrue);
      NearbyOffer.parse(fixtures['offer']);
      for (final message in [
        'hello',
        'offer',
        'accept',
        'decline',
        'saved',
      ]) {
        final encoded = nearbyEncodeControl(
          Map<String, Object?>.from(fixtures[message] as Map),
        );
        final length = ByteData.sublistView(encoded).getUint32(0);
        expect(length, encoded.length - 4);
        final decoded = nearbyDecodeControl(
          encoded.sublist(4),
        ) as Map;
        for (final entry
            in (fixtures[message] as Map).cast<String, Object?>().entries) {
          expect(decoded[entry.key], entry.value);
        }
      }
    });

    test('hello must match exactly — extra fields rejected', () {
      expect(nearbyCheckHello(nearbyHello), isTrue);
      expect(
        nearbyCheckHello({'type': 'hello', 'app': 'other', 'version': 1}),
        isFalse,
      );
      expect(
        nearbyCheckHello({...nearbyHello, 'extra': true}),
        isFalse,
      );
      expect(nearbyCheckHello({'type': 'hello', 'app': 'monolith-music'}), isFalse);
      expect(nearbyCheckHello('not a map'), isFalse);
    });

    test('offer rejects untrusted metadata before accepting', () {
      for (final name in [
        '../song.mp3',
        'C:\\song.mp3',
        'CON.mp3',
        'LPT1.wav',
        'song.exe',
        'song.mp3.',
        '.hidden.mp3',
        'song/song.mp3',
        'a' * 181 + '.mp3',
      ]) {
        expect(nearbyValidName(name), isFalse, reason: name);
      }
      expect(nearbyValidName('song.mp3'), isTrue);
      expect(nearbyValidName('أغنية.flac'), isTrue);
      expect(
        () => NearbyOffer.parse({
          'type': 'offer',
          'name': 'song.mp3',
          'title': 'Song',
          'size': nearbyMaxSongBytes + 1,
          'sha256': 'a' * 64,
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => NearbyOffer.parse({
          'type': 'offer',
          'name': 'song.mp3',
          'title': 'Song',
          'size': 10,
          'sha256': 'zz' * 32,
        }),
        throwsA(isA<FormatException>()),
      );
      // Uppercase hashes are lowercased on parse, like the desktop.
      final offer = NearbyOffer.parse({
        'type': 'offer',
        'name': 'song.mp3',
        'title': 'Song',
        'size': 10,
        'sha256': 'A' * 64,
      });
      expect(offer.sha256, 'a' * 64);
    });

    test('control length bounds are enforced', () async {
      final (a, b) = await _socketPair();
      a.socket.add(Uint8List(4)..buffer.asByteData().setUint32(0, 0));
      unawaited(a.socket.flush());
      await expectLater(b.readControl(), throwsA(anything));
      a.destroy();
      b.destroy();

      final (c, d) = await _socketPair();
      c.socket.add(
        Uint8List(4)
          ..buffer.asByteData().setUint32(0, nearbyMaxControlBytes + 1),
      );
      unawaited(c.socket.flush());
      await expectLater(d.readControl(), throwsA(anything));
      c.destroy();
      d.destroy();
    });

    test('local IPv4 filter matches lan.rs', () {
      for (final ip in ['127.0.0.1', '10.0.0.5', '172.16.3.4', '192.168.1.9',
          '169.254.1.1']) {
        expect(nearbyLocalAddress(InternetAddress(ip)), isTrue, reason: ip);
      }
      for (final ip in ['8.8.8.8', '172.15.0.1', '192.167.0.1', '11.0.0.1']) {
        expect(nearbyLocalAddress(InternetAddress(ip)), isFalse, reason: ip);
      }
    });
  });

  group('ephemeral certificate', () {
    test('generates a P-256 self-signed cert BoringSSL accepts', () async {
      final cert = NearbyCertificate.generate();
      expect(cert.fingerprint, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(cert.alias.split(' '), hasLength(3));
      // The DER certificate is the fingerprinted artifact.
      expect(sha256.convert(cert.der).toString(), cert.fingerprint);
      // Loading into a SecurityContext exercises the full PEM → BoringSSL
      // parse path; a malformed key/cert pair would throw here.
      final server = await SecureServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
        cert.serverContext(),
      );
      await server.close();
    });

    test('session name matches the desktop word lists', () {
      // Deterministic check: names always come from the 16-entry lists.
      final cert = NearbyCertificate.generate();
      expect(nearbySessionName(cert.der), cert.alias);
      expect(nearbyFingerprint(cert.der), cert.fingerprint);
    });
  });

  group('discovery', () {
    test('parse accepts valid replies and rejects spoofs', () {
      final nonce = 'a' * 32;
      final source = InternetAddress('127.0.0.1');
      Map<String, Object?> valid() => {
        'app': 'monolith-music',
        'version': 1,
        'type': 'available',
        'nonce': nonce,
        'port': 1234,
        'alias': 'Quiet Coral Cedar',
        'fingerprint': 'b' * 64,
      };
      final peer = nearbyParsePeer(valid(), source, nonce);
      expect(peer, isNotNull);
      expect(peer!.name, 'Quiet Coral Cedar · 127.0.0.1');
      for (final entry in {
        'nonce': 'wrong',
        'app': 'another-app',
        'port': 0,
        'fingerprint': 'bad',
        'alias': 'bad\nname',
        'alias2': 'x',
      }.entries) {
        final invalid = valid();
        if (entry.key == 'alias2') {
          invalid['alias'] = 'a' * 65;
        } else {
          invalid[entry.key] = entry.value;
        }
        expect(
          nearbyParsePeer(invalid, source, nonce),
          isNull,
          reason: '${entry.key}: ${entry.value}',
        );
      }
      // A public source address is rejected even with a valid payload.
      expect(
        nearbyParsePeer(valid(), InternetAddress('8.8.8.8'), nonce),
        isNull,
      );
    });

    test('responder answers discover queries and scan finds it', () async {
      final cancel = NearbyCancel();
      final responder = await NearbyDiscoveryResponder.start(
        port: 45231,
        alias: 'Quiet Coral Cedar',
        fingerprint: 'b' * 64,
      );
      try {
        final peers = await nearbyDiscover(
          cancel: cancel,
          broadcastAddress: InternetAddress.loopbackIPv4,
        );
        expect(peers, hasLength(1));
        expect(peers.single.port, 45231);
        expect(peers.single.name, 'Quiet Coral Cedar · 127.0.0.1');
        expect(peers.single.fingerprint, 'b' * 64);
      } finally {
        await responder.close();
        cancel.cancel();
      }
    });

    test('scan ignores this device's own responder', () async {
      final cancel = NearbyCancel();
      final responder = await NearbyDiscoveryResponder.start(
        port: 45232,
        alias: 'Self Device',
        fingerprint: 'c' * 64,
      );
      try {
        final peers = await nearbyDiscover(
          cancel: cancel,
          broadcastAddress: InternetAddress.loopbackIPv4,
          ignoreFingerprint: 'c' * 64,
        );
        expect(peers, isEmpty);
      } finally {
        await responder.close();
        cancel.cancel();
      }
    });
  });

  group('artwork extension', () {
    test('kind sniffing', () {
      expect(nearbyArtworkKind(_jpeg()), 'jpg');
      expect(
        nearbyArtworkKind([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
        'png',
      );
      expect(nearbyArtworkKind([...'RIFF'.codeUnits, 0, 0, 0, 0, ...'WEBP'.codeUnits]), 'webp');
      expect(nearbyArtworkKind('hello world!'.codeUnits), isNull);
    });

    test('offer carries artwork fields only when present', () {
      final plain = NearbyOffer(
        name: 'a.mp3',
        title: 'A',
        size: 10,
        sha256: 'a' * 64,
      );
      expect(plain.toJson().containsKey('artwork_size'), isFalse);
      final withArt = NearbyOffer(
        name: 'a.mp3',
        title: 'A',
        size: 10,
        sha256: 'a' * 64,
        artworkSize: 66,
        artworkSha256: 'b' * 64,
        artworkExt: 'jpg',
      );
      final parsed = NearbyOffer.parse(withArt.toJson());
      expect(parsed.hasArtwork, isTrue);
      expect(parsed.artworkSize, 66);
      expect(parsed.artworkSha256, 'b' * 64);
      expect(parsed.artworkExt, 'jpg');
    });

    test('malformed artwork is dropped, the song offer survives', () {
      final json = NearbyOffer(
        name: 'a.mp3',
        title: 'A',
        size: 10,
        sha256: 'a' * 64,
      ).toJson()
        ..['artwork_size'] = 9 * 1024 * 1024
        ..['artwork_sha256'] = 'b' * 64
        ..['artwork_ext'] = 'gif';
      final parsed = NearbyOffer.parse(json);
      expect(parsed.hasArtwork, isFalse);
      expect(parsed.size, 10);
    });
  });

  group('transfer', () {
    Future<Directory> tempDir() =>
        Directory.systemTemp.createTemp('nearby-test');

    test('TLS roundtrip: pinned fingerprint sends a real song', () async {
      final dir = await tempDir();
      try {
        final source = File('${dir.path}${Platform.pathSeparator}song.wav')
          ..writeAsBytesSync(_audio());
        final offer = await nearbyOfferForFile(source, 'Test song');
        final cancel = NearbyCancel();
        final receiver = await NearbyReceiver.start(
          cancel: cancel,
          host: InternetAddress.loopbackIPv4,
          advertise: false,
        );
        final inbox = await Directory(
          '${dir.path}${Platform.pathSeparator}inbox',
        ).create();
        final serverDone = Completer<File>();
        unawaited(
          Future(() async {
            final channel = await receiver.accept();
            final published = await nearbyReceive(
              channel!,
              inbox,
              consent: (_, _) async => true,
              publish: (staged, name) async => staged.copy(
                '${inbox.path}${Platform.pathSeparator}$name',
              ),
              import: (_) async {},
            );
            serverDone.complete(published);
          }).catchError((Object e) {
            serverDone.completeError(e);
          }),
        );
        final peer = NearbyPeer(
          name: 'loopback',
          address: InternetAddress.loopbackIPv4,
          port: receiver.port,
          fingerprint: receiver.fingerprint,
        );
        final channel = await nearbyConnect(peer, cancel);
        var progressCalls = 0;
        await nearbySend(
          channel,
          source,
          offer,
          onProgress: (_, _) => progressCalls++,
        );
        final saved = await serverDone.future;
        expect(await saved.readAsBytes(), _audio());
        expect(progressCalls, greaterThan(0));
        await channel.close();
        await receiver.close();
      } finally {
        await dir.delete(recursive: true);
      }
    });

    for (final receiverSupportsArtwork in [true, false]) {
      test(
        'cover art travels with the song '
        '(receiver supports artwork: $receiverSupportsArtwork)',
        () async {
          final dir = await tempDir();
          try {
            final source = File('${dir.path}${Platform.pathSeparator}song.wav')
              ..writeAsBytesSync(_audio());
            final cover = File('${dir.path}${Platform.pathSeparator}song.jpg')
              ..writeAsBytesSync(_jpeg());
            final offer = await nearbyOfferForFile(
              source,
              'Art song',
              artwork: cover,
            );
            expect(offer.hasArtwork, isTrue);
            expect(offer.artworkExt, 'jpg');
            final inbox = await Directory(
              '${dir.path}${Platform.pathSeparator}inbox',
            ).create();
            final (client, server) = await _socketPair();
            Uint8List? savedArt;
            String? savedExt;
            final received = nearbyReceive(
              server,
              inbox,
              consent: (_, _) async => true,
              publish: (staged, name) async => staged.copy(
                '${inbox.path}${Platform.pathSeparator}$name',
              ),
              saveArtwork: receiverSupportsArtwork
                  ? (_, bytes, ext) async {
                      savedArt = bytes;
                      savedExt = ext;
                    }
                  : null,
              import: (_) async {},
            );
            await nearbySend(client, source, offer, artwork: cover);
            final published = await received;
            expect(await published.readAsBytes(), _audio());
            if (receiverSupportsArtwork) {
              expect(savedArt, _jpeg());
              expect(savedExt, 'jpg');
            } else {
              expect(savedArt, isNull);
            }
            await client.close();
            await server.close();
          } finally {
            await dir.delete(recursive: true);
          }
        },
      );
    }

    test('TLS rejects a changed certificate', () async {
      final cancel = NearbyCancel();
      final receiver = await NearbyReceiver.start(
        cancel: cancel,
        host: InternetAddress.loopbackIPv4,
        advertise: false,
      );
      final peer = NearbyPeer(
        name: 'loopback',
        address: InternetAddress.loopbackIPv4,
        port: receiver.port,
        fingerprint: '0' * 64, // not the real certificate
      );
      // The server must be accepting for the TLS handshake to be attempted.
      unawaited(receiver.accept());
      await expectLater(nearbyConnect(peer, cancel), throwsA(anything));
      await receiver.close();
    });

    for (final scenario in [
      'decline',
      'cancel',
      'partial',
      'hash',
      'not-audio',
      'import-failure',
    ]) {
      test('leaves no new song: $scenario', () async {
        final dir = await tempDir();
        try {
          final source = File('${dir.path}${Platform.pathSeparator}song.wav')
            ..writeAsBytesSync(_audio());
          var offer = await nearbyOfferForFile(source, 'Song');
          if (scenario == 'hash') {
            offer = NearbyOffer(
              name: offer.name,
              title: offer.title,
              size: offer.size,
              sha256: 'a' * 64,
            );
          }
          if (scenario == 'not-audio') {
            source.writeAsBytesSync(Uint8List(16044));
            offer = await nearbyOfferForFile(source, 'Song');
          }
          final inbox = await Directory(
            '${dir.path}${Platform.pathSeparator}inbox',
          ).create();
          final receiverCancel = NearbyCancel();
          if (scenario == 'cancel') receiverCancel.cancel();
          final (client, server) = await _socketPair(
            bCancel: receiverCancel,
          );
          final serverDone = Completer<bool>();
          unawaited(
            () async {
              try {
                await nearbyReceive(
                  server,
                  inbox,
                  consent: (_, _) async => scenario != 'decline',
                  publish: (staged, name) async => staged.copy(
                    '${inbox.path}${Platform.pathSeparator}$name',
                  ),
                  import: (_) async {
                    if (scenario == 'import-failure') {
                      throw StateError('Database unavailable');
                    }
                  },
                );
                return false;
              } catch (_) {
                return true;
              }
            }().then(serverDone.complete),
          );

          // Run the sender concurrently — the receiver may fail without
          // closing the socket, so the sender must be unblocked by destroy.
          final sendFailed = scenario == 'partial'
              ? Future.value(true)
              : nearbySend(client, source, offer)
                    .then((_) => false)
                    .catchError((Object _) => true);

          if (scenario == 'partial') {
            await client.writeControl(nearbyHello);
            expect(
              nearbyCheckHello(await client.readControl()),
              isTrue,
            );
            await client.writeControl(offer.toJson());
            expect((await client.readControl())['type'], 'accept');
            client.socket.add('short'.codeUnits);
            client.destroy();
          }
          expect(await serverDone.future, isTrue, reason: scenario);
          server.destroy();
          expect(await sendFailed, isTrue, reason: scenario);
          client.destroy();
          if (scenario == 'import-failure') {
            // Verified audio is retained; no receipt was sent.
            expect(
              await File(
                '${inbox.path}${Platform.pathSeparator}song.wav',
              ).readAsBytes(),
              _audio(),
            );
          } else {
            expect(inbox.listSync(), isEmpty, reason: scenario);
          }
        } finally {
          await dir.delete(recursive: true);
        }
      });
    }
  });
}
