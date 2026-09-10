import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monolith/src/core/services/shared_audio_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('monolith/shared_audio');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  test(
    'drains cold-start audio and subsequent warm-start notifications once',
    () async {
      final received = <Map<Object?, Object?>>[];
      var pending = <Map<String, Object>>[
        {'path': 'cold.mp3'},
      ];
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'takePending');
        final batch = pending;
        pending = [];
        return batch;
      });
      final service = SharedAudioService(
        onImport: (results) async {
          received.addAll(results);
        },
      );
      await service.start();
      expect(received.single['path'], 'cold.mp3');
      pending.add({'path': 'warm.mp3'});
      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(const MethodCall('ready')),
        (_) {},
      );
      expect(received.map((e) => e['path']), ['cold.mp3', 'warm.mp3']);
      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(const MethodCall('ready')),
        (_) {},
      );
      expect(received, hasLength(2));
      service.dispose();
      messenger.setMockMethodCallHandler(channel, null);
    },
  );

  test(
    'reports native copy failure instead of claiming a successful import',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => [
          {'error': 'No space left'},
        ],
      );
      List<Map<Object?, Object?>>? received;
      final service = SharedAudioService(
        onImport: (results) async {
          received = results;
        },
      );
      await service.start();
      expect(received!.single['error'], 'No space left');
      service.dispose();
      messenger.setMockMethodCallHandler(channel, null);
    },
  );
}
