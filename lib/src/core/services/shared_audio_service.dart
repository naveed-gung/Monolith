import 'dart:async';
import 'package:flutter/services.dart';

/// Separate from the import-progress channel so listeners cannot replace it.
class SharedAudioService {
  SharedAudioService({required this.onImport, MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('monolith/shared_audio');

  final MethodChannel _channel;
  final Future<void> Function(List<Map<Object?, Object?>> results) onImport;
  bool _disposed = false;
  Future<void> _pending = Future.value();

  Future<void> start() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'ready') await _drain();
    });
    await _drain();
  }

  Future<void> _drain() {
    _pending = _pending
        .then((_) async {
          if (_disposed) return;
          try {
            final results = await _channel.invokeListMethod<Object?>(
              'takePending',
            );
            if (!_disposed && results != null && results.isNotEmpty) {
              await onImport(
                results
                    .whereType<Map>()
                    .map((e) => Map<Object?, Object?>.from(e))
                    .toList(),
              );
            }
          } on MissingPluginException {
            // Non-Android platforms have no incoming-content bridge.
          } on PlatformException {
            // Another ready notification can retry a transient platform failure.
          }
        })
        .catchError((Object _) {});
    return _pending;
  }

  void dispose() {
    _disposed = true;
    _channel.setMethodCallHandler(null);
  }
}
