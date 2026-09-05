/// Playback and appearance enums for the Monolith 2.0 domain layer.
///
/// Pure Dart — no Flutter imports — so these stay usable from every layer
/// (`ui → domain ← data`) and are trivially unit-testable.
library;

/// How playback behaves when a track finishes.
enum RepeatMode { off, all, one }

/// Whether advancing through the queue shuffles.
enum ShuffleMode { off, all }

/// Light/dark/system appearance preference.
enum ThemePreference { system, light, dark }

/// Named accent-color presets.
///
/// Value names intentionally mirror the v1 `AccentPreset` enum in
/// `lib/src/app/theme/design_tokens.dart` so persisted preference strings
/// migrate 1:1 when the new settings layer takes over.
enum AccentPreset { coral, violet, ocean, lime, amber, magenta }
