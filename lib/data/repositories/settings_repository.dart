import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/enums.dart';

/// Typed settings over [SharedPreferences].
///
/// Load-once + write-through: values are read into memory when the repository
/// is constructed (cheap — SharedPreferences is already in-memory), getters
/// are synchronous, and every setter updates the cache before persisting.
///
/// Keys live under a dedicated `monolith.settings.` namespace so they never
/// collide with the v1 `pref_*` keys written by the old controller; migrating
/// those values happens in a later phase.
class SettingsRepository {
  SettingsRepository(SharedPreferences prefs)
    : themePreference =
          _decodeEnum(ThemePreference.values, prefs.getString(_kTheme)) ??
          ThemePreference.system,
      accentPreset =
          _decodeEnum(AccentPreset.values, prefs.getString(_kAccent)) ??
          AccentPreset.coral,
      downloadsOnWifi = prefs.getBool(_kDownloadsOnWifi) ?? true,
      normalizeAudio = prefs.getBool(_kNormalizeAudio) ?? true,
      smoothTransitions = prefs.getBool(_kSmoothTransitions) ?? true,
      reduceVisualEffects = prefs.getBool(_kReduceVisualEffects) ?? false,
      hapticsEnabled = prefs.getBool(_kHapticsEnabled) ?? true,
      backupReminderLastShownAt = _decodeDate(
        prefs.getString(_kBackupReminderLastShownAt),
      ),
      hasSeenBackupIntro = prefs.getBool(_kHasSeenBackupIntro) ?? false,
      _prefs = prefs;

  final SharedPreferences _prefs;

  // -- Keys -----------------------------------------------------------------

  static const String _prefix = 'monolith.settings.';
  static const String _kTheme = '${_prefix}theme';
  static const String _kAccent = '${_prefix}accent';
  static const String _kDownloadsOnWifi = '${_prefix}downloads_on_wifi';
  static const String _kNormalizeAudio = '${_prefix}normalize_audio';
  static const String _kSmoothTransitions = '${_prefix}smooth_transitions';
  static const String _kReduceVisualEffects = '${_prefix}reduce_visual_effects';
  static const String _kHapticsEnabled = '${_prefix}haptics_enabled';
  static const String _kBackupReminderLastShownAt =
      '${_prefix}backup_reminder_last_shown_at';
  static const String _kHasSeenBackupIntro = '${_prefix}has_seen_backup_intro';

  // -- Cached state (write-through) -----------------------------------------

  ThemePreference themePreference;
  AccentPreset accentPreset;

  /// Only download over unmetered networks.
  bool downloadsOnWifi;

  /// Loudness normalisation across tracks.
  bool normalizeAudio;

  /// Crossfade/gapless transitions between tracks.
  bool smoothTransitions;

  /// Disables decorative motion for low-end hardware.
  bool reduceVisualEffects;
  bool hapticsEnabled;

  /// Last time the backup reminder card was surfaced (null = never).
  DateTime? backupReminderLastShownAt;

  /// Whether the one-time Backup & Restore intro was acknowledged.
  bool hasSeenBackupIntro;

  // -- Write-through setters --------------------------------------------------

  Future<void> setThemePreference(ThemePreference value) async {
    themePreference = value;
    await _prefs.setString(_kTheme, value.name);
  }

  Future<void> setAccentPreset(AccentPreset value) async {
    accentPreset = value;
    await _prefs.setString(_kAccent, value.name);
  }

  Future<void> setDownloadsOnWifi(bool value) async {
    downloadsOnWifi = value;
    await _prefs.setBool(_kDownloadsOnWifi, value);
  }

  Future<void> setNormalizeAudio(bool value) async {
    normalizeAudio = value;
    await _prefs.setBool(_kNormalizeAudio, value);
  }

  Future<void> setSmoothTransitions(bool value) async {
    smoothTransitions = value;
    await _prefs.setBool(_kSmoothTransitions, value);
  }

  Future<void> setReduceVisualEffects(bool value) async {
    reduceVisualEffects = value;
    await _prefs.setBool(_kReduceVisualEffects, value);
  }

  Future<void> setHapticsEnabled(bool value) async {
    hapticsEnabled = value;
    await _prefs.setBool(_kHapticsEnabled, value);
  }

  Future<void> setBackupReminderLastShownAt(DateTime? value) async {
    backupReminderLastShownAt = value;
    if (value == null) {
      await _prefs.remove(_kBackupReminderLastShownAt);
    } else {
      await _prefs.setString(
        _kBackupReminderLastShownAt,
        value.toIso8601String(),
      );
    }
  }

  Future<void> setHasSeenBackupIntro(bool value) async {
    hasSeenBackupIntro = value;
    await _prefs.setBool(_kHasSeenBackupIntro, value);
  }

  // -- Decoders ---------------------------------------------------------------

  static T? _decodeEnum<T extends Enum>(List<T> values, String? raw) {
    if (raw == null) return null;
    for (final value in values) {
      if (value.name == raw) return value;
    }
    return null;
  }

  static DateTime? _decodeDate(String? raw) =>
      raw == null ? null : DateTime.tryParse(raw);
}
