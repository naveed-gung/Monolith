# Media Playback Integration

![Media playback pipeline](assets/media-playback-pipeline.svg)

The pipeline diagram captures the actual runtime path Monolith now uses, from selecting a track to publishing metadata into the system playback surfaces.

## Goal

Monolith exposes active playback to operating-system media surfaces so users can control playback outside the app.

This includes:

- Android media notifications
- Android notification-center transport deck
- iOS lock-screen now-playing information
- headset and system media button support

## Stack

Monolith uses:

- `just_audio` for playback
- `just_audio_background` for background media-session integration
- `audio_session` for explicit music-session configuration

The app currently uses a single `AudioPlayer`, which matches the intended use case for `just_audio_background`.

## Initialization

Background media integration is initialized in `lib/main.dart` before the app starts.

Responsibilities:

- initialize Flutter bindings
- initialize the background playback plugin
- define the Android notification channel used for playback

The app controller then configures `AudioSessionConfiguration.music()` during bootstrap so iOS treats Monolith as a foreground music player rather than leaving that classification to plugin defaults.

If this initialization is removed or moved after `runApp`, system media surfaces will not work reliably.

## Track Metadata

When Monolith activates a playable track, it loads an audio source tagged with a `MediaItem`.

That metadata includes:

- track ID
- title
- artist
- album
- genre
- duration when known
- artwork URI when a file-based or remote artwork asset is available

This metadata is what appears in Android notifications and on the iOS lock screen.

## Platform Configuration

### Android

The Android manifest includes:

- `WAKE_LOCK`
- `FOREGROUND_SERVICE`
- `FOREGROUND_SERVICE_MEDIA_PLAYBACK`
- `AudioService` service declaration
- `MediaButtonReceiver` receiver declaration
- `AudioServiceActivity` as the activity base class entry

These entries are required for the media session to publish foreground playback correctly.

### iOS

The iOS runner declares:

- `UIBackgroundModes`
  - `audio`

And the Dart playback layer explicitly configures a music audio session using `audio_session`.

Without this capability, iOS will not keep audio playback integrated with background and lock-screen behaviors the way users expect.

## Current Limitations

- Tracks with only `artworkQueryId` and no resolvable file or URL artwork may not show album art in system media surfaces, although title and artist metadata will still be available.
- iOS build validation must be done on macOS.
- iOS does not expose an Android-style notification shade media deck; the equivalent surfaces are Lock Screen and Control Center.
- Monolith currently exposes a single-player model. More advanced custom actions would require a deeper `audio_service` integration.

## Debugging Checklist

If lock-screen or notification controls are missing:

1. Confirm the selected track has a valid local `filePath`.
2. Confirm the track was loaded through the normal controller path rather than a test stub.
3. Re-run `flutter pub get` after dependency changes.
4. Rebuild the Android app after manifest updates.
5. On iOS, rebuild from a project that includes the updated `Info.plist` background audio entry and the controller's audio-session configuration.

If metadata appears but artwork does not:

1. Check `track.artworkFilePath` for a real existing file.
2. If using a remote image, confirm `track.artworkUrl` is a valid URI.
3. Remember that `QueryArtworkWidget`-only artwork is a UI-layer convenience and does not automatically map to a system media artwork URI.

## Future Enhancements

Possible next steps if playback behavior becomes more advanced:

- move from `just_audio_background` to direct `audio_service` orchestration
- add richer queue metadata and custom notification actions
- add artwork caching for device-library tracks whose artwork is currently only accessible through query IDs
