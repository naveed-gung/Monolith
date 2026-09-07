import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:monolith/src/core/services/audio_stream_transfer.dart';

class _Client extends http.BaseClient {
  _Client(this.handle);
  final Future<http.StreamedResponse> Function(http.BaseRequest) handle;
  int requests = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests++;
    return handle(request);
  }

  @override
  void close() {}
}

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('audio_transport_');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  Future<void> run(
    _Client client, {
    int size = 8,
    Duration timeout = const Duration(seconds: 1),
    AudioStreamTransfer? transfer,
  }) =>
      (transfer ??
              AudioStreamTransfer(
                client: client,
                timeout: timeout,
                rangeSize: 1024 * 1024,
              ))
          .download(
            url: Uri.parse('https://audio.example/playback?c=ANDROID_SDKLESS'),
            size: size,
            destination: File('${root.path}/audio.part'),
            onProgress: (_) {},
          );
  test('requests bounded ranges and writes each byte once', () async {
    const size = 1024 * 1024 + 5;
    final client = _Client((request) async {
      final range = request.url.queryParameters['range']!
          .split('-')
          .map(int.parse)
          .toList();
      return http.StreamedResponse(
        Stream.value(List.filled(range[1] - range[0] + 1, 7)),
        206,
        headers: {'content-range': 'bytes ${range[0]}-${range[1]}/$size'},
      );
    });
    await run(client, size: size);
    expect(client.requests, 2);
    expect(await File('${root.path}/audio.part').length(), size);
  });
  test(
    'empty successful response fails instead of repeating forever',
    () async {
      final client = _Client(
        (_) async => http.StreamedResponse(const Stream.empty(), 200),
      );
      await expectLater(run(client), throwsStateError);
      expect(client.requests, 1);
    },
  );
  test(
    '403 is returned immediately without an internal manifest retry',
    () async {
      final client = _Client(
        (_) async => http.StreamedResponse(const Stream.empty(), 403),
      );
      await expectLater(run(client), throwsA(isA<HttpException>()));
      expect(client.requests, 1);
    },
  );
  test('truncated and oversized responses are never accepted', () async {
    for (final size in [3, 12]) {
      final client = _Client(
        (_) async =>
            http.StreamedResponse(Stream.value(List.filled(size, 0)), 200),
      );
      await expectLater(run(client), throwsStateError);
    }
  });
  test(
    'silent stream times out even when cancellation never completes',
    () async {
      final stream = StreamController<List<int>>(
        onCancel: () => Completer<void>().future,
      );
      final client = _Client(
        (_) async => http.StreamedResponse(stream.stream, 200),
      );
      await expectLater(
        run(client, timeout: const Duration(milliseconds: 30)),
        throwsA(isA<TimeoutException>()),
      );
    },
  );
  test(
    'cancel during response preparation does not wait for the server',
    () async {
      final requested = Completer<void>();
      final client = _Client((_) {
        requested.complete();
        return Completer<http.StreamedResponse>().future;
      });
      final transfer = AudioStreamTransfer(client: client);
      final work = run(client, transfer: transfer);
      final assertion = expectLater(work, throwsStateError);
      await requested.future;
      transfer.cancel();
      await assertion.timeout(const Duration(seconds: 1));
    },
  );
}
