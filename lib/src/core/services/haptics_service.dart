import 'package:flutter/services.dart';

/// How strong a haptic tap should feel. Mapped onto Flutter's built-in
/// [HapticFeedback] primitives — no extra dependency, works on the iPhone's
/// Taptic Engine and Android vibrators alike.
enum HapticStrength { selection, light, medium, heavy }

/// Thin wrapper around [HapticFeedback] with a global on/off switch.
class HapticsService {
  HapticsService({this.enabled = true});

  bool enabled;

  Future<void> tap([HapticStrength strength = HapticStrength.light]) async {
    if (!enabled) return;
    // Some Android OEMs/devices without a vibrator (or with VIBRATE absent)
    // throw from the platform channel — never let a cosmetic tap crash the UI.
    try {
      switch (strength) {
        case HapticStrength.selection:
          await HapticFeedback.selectionClick();
        case HapticStrength.light:
          await HapticFeedback.lightImpact();
        case HapticStrength.medium:
          await HapticFeedback.mediumImpact();
        case HapticStrength.heavy:
          await HapticFeedback.heavyImpact();
      }
    } catch (_) {
      // No haptics hardware / permission — silently ignore.
    }
  }
}
