import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monolith/src/core/services/native_audio_extractor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(
    () =>
        messenger.setMockMethodCallHandler(NativeAudioExtractor.channel, null),
  );
  test(
    'extraction and cancellation address the same job without Music import calls',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(NativeAudioExtractor.channel, (
        call,
      ) async {
        calls.add(call);
        return null;
      });
      final extractor = NativeAudioExtractor();
      await extractor.extract(
        'song-2',
        '/cache/source.mp4',
        '/cache/audio.m4a',
      );
      await extractor.cancel('song-2');
      expect(calls.map((c) => c.method), [
        'extractAudio',
        'cancelAudioExtraction',
      ]);
      expect(calls.first.arguments, {
        'id': 'song-2',
        'input': '/cache/source.mp4',
        'output': '/cache/audio.m4a',
      });
      expect(calls.last.arguments, {'id': 'song-2'});
    },
  );
  test('native extraction failure remains a failure', () async {
    messenger.setMockMethodCallHandler(NativeAudioExtractor.channel, (_) async {
      throw PlatformException(
        code: 'audio_extraction',
        message: 'No AAC audio',
      );
    });
    await expectLater(
      NativeAudioExtractor().extract('song', '/in.mp4', '/out.m4a'),
      throwsA(isA<PlatformException>()),
    );
  });
}
