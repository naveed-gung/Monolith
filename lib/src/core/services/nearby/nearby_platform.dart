import 'dart:async';

import 'package:flutter/services.dart';

/// Android needs a `WifiManager.MulticastLock` held while UDP broadcast
/// datagrams are received; iOS needs nothing extra. The lock lives only while
/// a Share picker or Receive session is open.
class NearbyPlatform {
  NearbyPlatform._();

  static const _channel = MethodChannel('monolith/nearby');
  static bool _held = false;

  static Future<void> acquireMulticastLock() async {
    if (_held) return;
    try {
      await _channel.invokeMethod<void>('acquireMulticastLock');
      _held = true;
    } on MissingPluginException {
      // Non-Android platforms have no multicast-lock requirement.
    } on PlatformException {
      // A denied lock degrades discovery to send-only; share still works.
    }
  }

  static Future<void> releaseMulticastLock() async {
    if (!_held) return;
    _held = false;
    try {
      await _channel.invokeMethod<void>('releaseMulticastLock');
    } on MissingPluginException {
      // Non-Android platforms have no multicast-lock requirement.
    } on PlatformException {
      // Released or never held on the platform side — nothing more to do.
    }
  }
}
