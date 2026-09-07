import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:http/http.dart' as http;

/// Bounded transport for a resolved, non-fragmented audio stream. Owning the
/// requests avoids the extractor's internal manifest/retry loop on empty/403
/// responses, including cancellation that waits for that loop to finish.
class AudioStreamTransfer {
  AudioStreamTransfer({
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
    this.rangeSize = 10 * 1024 * 1024,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;
  final int rangeSize;
  final _cancelled = Completer<void>();
  bool get isCancelled => _cancelled.isCompleted;

  void cancel() {
    if (!isCancelled) _cancelled.complete();
    _client.close();
  }

  Future<T> _wait<T>(Future<T> future) => Future.any([
    future.timeout(timeout),
    _cancelled.future.then<T>((_) => throw StateError('Download cancelled')),
  ]);

  Future<void> download({
    required Uri url,
    required int size,
    required File destination,
    required void Function(int received) onProgress,
    Map<String, String> headers = const {},
  }) async {
    if (size <= 0) {
      throw StateError('The source did not provide an audio size.');
    }
    final sink = destination.openWrite();
    var received = 0;
    try {
      while (received < size) {
        if (isCancelled) throw StateError('Download cancelled');
        final start = received;
        final end = math.min(start + rangeSize, size) - 1;
        final android = url.queryParameters['c'] == 'ANDROID';
        final request = http.Request(
          'GET',
          android
              ? url
              : url.replace(
                  queryParameters: {
                    ...url.queryParameters,
                    'range': '$start-$end',
                  },
                ),
        );
        request.headers['User-Agent'] = 'Mozilla/5.0';
        request.headers.addAll(headers);
        if (android) request.headers['Range'] = 'bytes=$start-$end';
        final response = await _wait(_client.send(request));
        if (response.statusCode != 200 && response.statusCode != 206) {
          throw HttpException(
            'Audio source returned HTTP ${response.statusCode}',
          );
        }
        final contentRange = response.headers['content-range'];
        if (contentRange != null && contentRange != 'bytes $start-$end/$size') {
          throw StateError('The source returned an unexpected audio range.');
        }
        final iterator = StreamIterator(response.stream);
        try {
          while (await _wait(iterator.moveNext())) {
            final chunk = iterator.current;
            if (isCancelled) throw StateError('Download cancelled');
            received += chunk.length;
            if (received > end + 1) {
              throw StateError('The source ignored the requested audio range.');
            }
            sink.add(chunk);
            // Backpressure bounds buffered audio on phones.
            await sink.flush();
            onProgress(received);
          }
        } finally {
          // Never make completion depend on a stalled network cancellation.
          unawaited(iterator.cancel().catchError((Object _) {}));
        }
        if (received != end + 1) {
          throw StateError(
            received == start
                ? 'The source returned no audio bytes.'
                : 'The source stopped before the audio was complete.',
          );
        }
      }
    } finally {
      _client.close();
      await sink.close();
    }
  }
}
