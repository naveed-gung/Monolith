# Changelog

All notable changes to Monolith are documented here.

## [1.0.3] — 2026-06-03

### Fixed
- **iOS: freshly downloaded songs play on the first tap** — the new track's audio source is now loaded as soon as the download completes, instead of needing a force-quit + relaunch.
- **Heat & battery drain** — the shell no longer schedules a per-frame callback on every state change during playback, and the playback position UI (seek bar + time labels) now repaints in isolation behind `ValueNotifier`s, so the SoC gets idle gaps back.

### Added
- **Haptic feedback** on transport, navigation, and settings controls (toggle in Settings → Playback).
- **Apple Music import toggle** and a **Monolith folder** shortcut in Settings; the import prompt is relabelled Import / Cancel with a re-run action.
- **Smart playlists** — Recently added, Most played, Never played.
- **Lyrics view** — `.lrc` sidecar support with synced line highlighting.
- **Equalizer (Android)** — per-band graphic EQ in Settings → Sound, persisted.
- **Accent-following in-app logo** — the “m” brand mark matches the selected accent.

### Notes
- Per-accent home-screen launcher icons and a real FFT/waveform visualizer are planned for a follow-up (they need iOS-side native work + on-device verification).

[1.0.3]: https://github.com/naveed-gung/Monolith/releases/tag/v1.0.3

## [1.0.2] — 2026-06-03

### Added
- **Swipe navigation** — horizontal swipes move between Library, Downloads, and Search; a swipe-right also leaves Settings.
- **Tap-to-dismiss keyboard** — tapping anywhere off a text field closes the keyboard (no drag required).
- New coral **m** launcher icon for Android and iOS, matching the in-app now-playing logo.
- TrollStore / TrollStore Lite install notes and a "TrollStore Ready" badge.

### Fixed
- **iOS first-play bug** — a freshly downloaded track no longer reports `00:00 / 00:00` and stays silent until relaunch; the audio session is now configured for music playback at startup.
- **Add-to-playlist sheet** now rises above the keyboard instead of hiding behind it.
- The **Immersive canvas** toggle now actually controls the reactive artwork glow.
- **Open player** from Settings now slides Settings away to the right and raises the player with its own animation.

### Changed / Performance
- The reactive visualizer only runs while the player is open, playing, and immersive canvas is on — fixing excessive battery drain and heat.
- Capped the animated artwork-glow blur so it stays smooth on high-refresh displays.

[1.0.2]: https://github.com/naveed-gung/Monolith/releases/tag/v1.0.2
