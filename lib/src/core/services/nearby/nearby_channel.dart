import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'nearby_wire.dart';

/// Cancellation token shared by both transfer roles. Cancelling destroys the
/// socket so any blocked read/write wakes immediately, like the desktop's
/// `Arc<AtomicBool>` polling plus socket close.
class NearbyCancel {
  final Completer<void> _cancelled = Completer<void>();

  bool get cancelled => _cancelled.isCompleted;
  Future<void> get onCancel => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

/// Framed control records plus exact-size raw audio over a `Socket` (plain TCP
/// in tests, `SecureSocket` on the wire). Every socket wait has a 75-second
/// idle timeout and the connection expires absolutely after 15 minutes —
/// matching `Socket::check` in lan.rs.
class NearbyChannel {
  NearbyChannel(this.socket, {required this.cancel, DateTime? until})
    : until = until ?? DateTime.now().add(const Duration(minutes: 15));

  static const idleTimeout = Duration(seconds: 75);
  static const consentTimeout = Duration(seconds: 60);

  final Socket socket;
  final NearbyCancel cancel;
  final DateTime until;

  final _reader = _BufferedReader();
  StreamIterator<Uint8List>? _iterator;

  void _check() {
    if (cancel.cancelled) {
      throw const SocketException('Sharing cancelled.');
    }
    if (DateTime.now().isAfter(until)) {
      throw const SocketException('Sharing session timed out.');
    }
  }

  Future<T> _wait<T>(Future<T> future) {
    _check();
    return Future.any<T>([
      future,
      Future<T>.delayed(
        idleTimeout,
        () => throw const SocketException('Sharing session timed out.'),
      ),
      cancel.onCancel.then<T>(
        (_) => throw const SocketException('Sharing cancelled.'),
      ),
    ]);
  }

  void _ensureIterator() {
    _iterator ??= StreamIterator(socket);
  }

  /// Accumulate until the exact length, EOF or cancellation — never assume a
  /// socket read fills a header/body.
  Future<Uint8List> readExact(int count) async {
    while (_reader.length < count) {
      _check();
      _ensureIterator();
      if (!await _wait(_iterator!.moveNext())) {
        throw const SocketException(
          'Connection ended before the song arrived.',
        );
      }
      _reader.add(_iterator!.current);
    }
    return _reader.take(count);
  }

  Future<Map<String, Object?>> readControl() async {
    final header = await readExact(4);
    final length = header.buffer.asByteData().getUint32(0);
    if (length == 0 || length > nearbyMaxControlBytes) {
      throw const FormatException('Invalid sharing message length.');
    }
    final body = await readExact(length);
    final decoded = nearbyDecodeControl(body);
    return decoded is Map ? Map<String, Object?>.from(decoded) : const {};
  }

  Future<void> writeControl(Map<String, Object?> value) async {
    _check();
    socket.add(nearbyEncodeControl(value));
    await _wait(socket.flush());
  }

  /// Send exactly [size] raw audio bytes — no per-chunk header (nearby.rs
  /// `send`). Progress reports actual streamed byte counts.
  Future<void> sendBytes(
    Stream<List<int>> bytes,
    int size, {
    void Function(int sent, int total)? onProgress,
  }) async {
    var sent = 0;
    final counted = bytes.map((chunk) {
      sent += chunk.length;
      onProgress?.call(sent, size);
      return chunk;
    });
    await _wait(socket.addStream(counted));
    if (sent != size) {
      throw const SocketException('The source song changed during sharing.');
    }
    await _wait(socket.flush());
  }

  /// Stream exactly [size] raw audio bytes into [sink] (normally a file).
  /// Progress reports actual received byte counts.
  Future<void> receiveBytes(
    IOSink sink,
    int size, {
    void Function(int received, int total)? onProgress,
  }) async {
    var received = 0;
    while (received < size) {
      _check();
      final chunk = await readExact(
        (size - received) > 65536 ? 65536 : size - received,
      );
      received += chunk.length;
      sink.add(chunk);
      // Backpressure bounds buffered audio on phones.
      await _wait(sink.flush());
      onProgress?.call(received, size);
    }
  }

  /// Destroy the socket immediately; used for close/cancel so blocked native
  /// operations wake rather than waiting out the idle timeout.
  void destroy() {
    socket.destroy();
    unawaited(_iterator?.cancel());
  }

  Future<void> close() async {
    destroy();
  }
}

class _BufferedReader {
  final List<Uint8List> _chunks = [];
  int length = 0;

  void add(Uint8List chunk) {
    _chunks.add(chunk);
    length += chunk.length;
  }

  Uint8List take(int count) {
    final out = Uint8List(count);
    var offset = 0;
    while (offset < count) {
      final head = _chunks.first;
      final needed = count - offset;
      if (head.length <= needed) {
        out.setRange(offset, offset + head.length, head);
        offset += head.length;
        _chunks.removeAt(0);
      } else {
        out.setRange(offset, offset + needed, head);
        _chunks[0] = head.sublist(needed);
        offset += needed;
      }
    }
    length -= count;
    return out;
  }
}
