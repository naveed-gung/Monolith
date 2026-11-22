import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'nearby_channel.dart';
import 'nearby_wire.dart';

/// The v1 session state machines, matching `send`/`receive` in nearby.rs:
/// hello ↔ hello, offer → consent → accept/decline → exact-size raw audio →
/// SHA-256 + content probe → publish → `saved` receipt only after import
/// succeeds. EOF/timeout/errors/cancel never mean success.
///
/// When [offer] advertises artwork and the recipient answers
/// `{"type":"accept","artwork":true}`, exactly `artworkSize` bytes of
/// [artwork] follow the audio. Older recipients never ask, so nothing extra
/// is written and the stream stays v1-compatible.
Future<void> nearbySend(
  NearbyChannel channel,
  File source,
  NearbyOffer offer, {
  File? artwork,
  void Function(int sent, int total)? onProgress,
}) async {
  offer.validate();
  await channel.writeControl(nearbyHello);
  if (!nearbyCheckHello(await channel.readControl())) {
    throw const SocketException(
      'This device is not running a compatible Monolith sharing session.',
    );
  }
  await channel.writeControl(offer.toJson());
  final answer = await channel.readControl();
  if (answer['type'] != 'accept') {
    throw const SocketException(
      'The recipient declined or could not accept this song.',
    );
  }
  // Bound the stream to exactly the offered size — the desktop reads at most
  // `size` bytes even if the source file grows mid-transfer.
  await channel.sendBytes(
    source.openRead(0, offer.size),
    offer.size,
    onProgress: onProgress,
  );
  if (answer['artwork'] == true && offer.hasArtwork && artwork != null) {
    await channel.sendBytes(
      artwork.openRead(0, offer.artworkSize),
      offer.artworkSize,
    );
  }
  final receipt = await channel.readControl();
  if (receipt['type'] != 'saved' || receipt['sha256'] != offer.sha256) {
    throw const SocketException('No verified library receipt was received.');
  }
}

/// Receives one song over [channel]. [consent] is the recipient's explicit
/// per-song approval — capped at 60 seconds like the desktop consent timeout;
/// expiry or refusal sends `decline`. [publish] moves the verified staged file
/// into the library destination without overwriting and returns its path;
/// [import] runs the existing importer. A `saved` receipt is sent only after
/// both succeed — if publication succeeded but import failed the verified
/// audio is retained and no receipt is sent.
///
/// [saveArtwork], when given, opts into the artwork extension: the receiver
/// asks for the sidecar, always drains exactly `artworkSize` bytes (keeping
/// the stream in sync), and stores it beside the published song only when its
/// SHA-256 and image magic match. Bad artwork is dropped, never the song.
Future<File> nearbyReceive(
  NearbyChannel channel,
  Directory stagingDirectory, {
  required Future<bool> Function(NearbyOffer offer, String sender) consent,
  required Future<File> Function(File staged, String name) publish,
  required Future<void> Function(File published) import,
  Future<void> Function(File published, Uint8List bytes, String ext)?
  saveArtwork,
  void Function(int received, int total)? onProgress,
}) async {
  final sender = channel.socket.remoteAddress.address;
  final hello = await channel.readControl();
  if (!nearbyCheckHello(hello)) {
    throw const SocketException(
      'This device is not running a compatible Monolith sharing session.',
    );
  }
  await channel.writeControl(nearbyHello);
  final offer = NearbyOffer.parse(await channel.readControl());

  Future<File> failDecline() async {
    await channel.writeControl(const {'type': 'decline'});
    throw const SocketException('Incoming song declined.');
  }

  var approved = false;
  try {
    approved = await consent(offer, sender).timeout(
      NearbyChannel.consentTimeout,
      onTimeout: () => false,
    );
  } catch (_) {
    approved = false;
  }
  if (!approved || channel.cancel.cancelled) {
    return failDecline();
  }

  await stagingDirectory.create(recursive: true);
  // Session-owned staging file; removed on every unwind path.
  final staged = File(
    '${stagingDirectory.path}${Platform.pathSeparator}'
    '.monolith-sharing-${DateTime.now().microsecondsSinceEpoch}.part',
  );
  IOSink? sink;
  try {
    sink = staged.openWrite();
    final wantArtwork = offer.hasArtwork && saveArtwork != null;
    await channel.writeControl({
      'type': 'accept',
      if (wantArtwork) 'artwork': true,
    });
    await channel.receiveBytes(sink, offer.size, onProgress: onProgress);
    await sink.flush();
    await sink.close();
    sink = null;
    final artwork = wantArtwork
        ? await channel.readExact(offer.artworkSize)
        : null;

    if (channel.cancel.cancelled) {
      throw const SocketException('Sharing cancelled.');
    }
    final digest = await sha256.bind(staged.openRead()).first;
    if (digest.toString() != offer.sha256) {
      throw const SocketException(
        'Song integrity check failed. Incomplete file discarded.',
      );
    }
    // Probe content, not the extension, before publishing.
    if (!await nearbyLooksLikeAudio(staged)) {
      throw const SocketException('The received file is not audio.');
    }
    if (channel.cancel.cancelled) {
      throw const SocketException('Sharing cancelled.');
    }
    final published = await publish(staged, offer.name);
    if (artwork != null) {
      final kind = nearbyArtworkKind(artwork);
      if (kind != null &&
          sha256.convert(artwork).toString() == offer.artworkSha256) {
        try {
          await saveArtwork!(published, artwork, kind);
        } catch (_) {
          // Cover art is best-effort; the verified song still imports.
        }
      }
    }
    // Keep verified audio on disk if import fails; never claim it reached
    // the library.
    await import(published);
    await channel.writeControl({'type': 'saved', 'sha256': offer.sha256});
    return published;
  } finally {
    // Await so the handle is released before delete — Windows refuses to
    // remove a file a write stream still holds open.
    await sink?.close();
    if (await staged.exists()) {
      // Verified audio survives only inside `publish`; the .part staging file
      // is always removed on unwind.
      await staged.delete().catchError((Object _) => staged);
    }
  }
}

/// Builds the [NearbyOffer] a sender advertises for [file] — the same checks
/// the desktop performs before the first byte: real size 1…100 MB and a
/// SHA-256 of the stable snapshot actually being sent.
///
/// [artwork] is an optional cover sidecar (JPEG/PNG/WebP up to 8 MB). Anything
/// unreadable, oversized or not an image is silently left out of the offer.
Future<NearbyOffer> nearbyOfferForFile(
  File file,
  String title, {
  File? artwork,
}) async {
  final size = await file.length();
  if (size <= 0 || size > nearbyMaxSongBytes) {
    throw const SocketException('Choose a song under 100 MB.');
  }
  final name = file.uri.pathSegments.last;
  final cleaned = title
      .replaceAll(RegExp(r'[\x00-\x1f\x7f-\x9f]'), '')
      .trim();
  var artworkSize = 0;
  var artworkSha256 = '';
  var artworkExt = '';
  if (artwork != null) {
    try {
      final length = await artwork.length();
      if (length > 0 && length <= nearbyMaxArtworkBytes) {
        final bytes = await artwork.readAsBytes();
        final kind = nearbyArtworkKind(bytes);
        if (kind != null && bytes.length == length) {
          artworkSize = length;
          artworkSha256 = sha256.convert(bytes).toString();
          artworkExt = kind;
        }
      }
    } on FileSystemException {
      // Missing or unreadable cover: share the song without it.
    }
  }
  final offer = NearbyOffer(
    name: name,
    title: cleaned.length > 120 ? cleaned.substring(0, 120) : cleaned,
    size: size,
    sha256: (await sha256.bind(file.openRead()).first).toString(),
    artworkSize: artworkSize,
    artworkSha256: artworkSha256,
    artworkExt: artworkExt,
  );
  offer.validate();
  return offer;
}

/// Magic-byte audio probe — the mobile equivalent of the desktop's lofty
/// `guess_file_type` check. Sniffs RIFF/WAVE, ID3 + MPEG sync, OggS, fLaC,
/// FORM/AIFF and ISO-BMFF ftyp brands.
Future<bool> nearbyLooksLikeAudio(File file) async {
  final head = await file.openRead(0, 16).expand((c) => c).toList();
  if (head.length < 4) return false;
  bool at(int i, int b) => head.length > i && head[i] == b;
  String four(int i) =>
      head.length >= i + 4 ? String.fromCharCodes(head.sublist(i, i + 4)) : '';
  if (four(0) == 'RIFF' && four(8) == 'WAVE') return true;
  if (four(0) == 'FORM' && (four(8) == 'AIFF' || four(8) == 'AIFC')) {
    return true;
  }
  if (four(0) == 'OggS') return true;
  if (four(0) == 'fLaC') return true;
  if (four(0) == 'ID3') return true;
  if (four(4) == 'ftyp') return true; // M4A/MP4 audio container
  // MPEG audio frame sync (0xFFEx) covers headerless MP3/AAC/ADTS streams.
  if (at(0, 0xff) && head.length > 1 && (head[1] & 0xe0) == 0xe0) return true;
  return false;
}
