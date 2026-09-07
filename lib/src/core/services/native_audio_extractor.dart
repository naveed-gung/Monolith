import 'dart:async';
import 'package:flutter/services.dart';

/// Extracts the AAC track from a downloaded MP4 without decoding/re-encoding.
class NativeAudioExtractor {
  static const channel = MethodChannel('monolith/media_import');
  Future<void> extract(String id, String input, String output) async {
    try {
      await channel
          .invokeMethod<void>('extractAudio', {
            'id': id,
            'input': input,
            'output': output,
          })
          .timeout(const Duration(seconds: 125));
    } on TimeoutException {
      await cancel(id);
      rethrow;
    }
  }

  Future<void> cancel(String id) async {
    try {
      await channel.invokeMethod<void>('cancelAudioExtraction', {'id': id});
    } on PlatformException {
      /* Native completion still reports failure. */
    } on MissingPluginException {
      /* No extraction was started. */
    }
  }
}
