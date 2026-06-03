# Changelog

All notable changes to Monolith are documented here.

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
