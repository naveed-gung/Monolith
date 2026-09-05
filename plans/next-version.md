# Monolith next version — execution plan

September 5, 2026. Preserve the existing uncommitted rebuild and live library.

## Findings

The live entry point still uses lib/src. New repositories and native bridges exist
alongside it. Music import scans via on_audio_query rather than using the native
picker. Swift incorrectly copies ipod-library URLs with FileManager and labels
every failure DRM. Storage exports only through sharing. Saved absolute iOS paths
can become stale after container relocation. Thumbnails already download for new
downloads, but have no request timeout. Live surfaces retain expensive blur.

## Execution order

1. Connect native Music import and Files export to the live UI, export accessible
   library assets through AVFoundation, retain honest protected/cloud statuses.
2. Recover relocated app-owned paths without losing metadata; preserve storage
   locations and application identity. Add regression coverage.
3. Refine the existing design with calm opaque surfaces, artwork decode limits,
   readable typography and lifecycle-aware animation. Preserve all feature routes.
4. Add GitHub release asset download and platform installation handoff. Android
   requires user-confirmed installation and matching signing identity. iOS update
   installation depends on the user's signing/distribution route.
5. Analyze, run regression tests, build and exercise the Pixel_10a emulator.
   iOS native compilation and real Music/Files flows require macOS/iPhone.

## Acceptance

Music import reports copied/skipped items; Files export reaches native picker;
existing metadata survives a relocated container; artwork remains available offline;
idle/background UI does not continuously animate; update files stay outside music;
checks and emulator results are recorded honestly. No publishing in this session.

## Confirmed existing feature inventory

The live app includes local library scanning; Files import; offline downloads;
search; artists/albums; user and smart playlists; favorites; metadata editing;
play counts; playback queue, shuffle and repeat; background audio; lyrics;
Android equalizer; storage management; themes, accent colors and haptics.
New repository layers coexist with the live controller and were preserved.

## Owner clarification

The iPhone uses TrollStore. The update panel uses TrollStore's documented
apple-magnifier install URL and also offers the downloaded IPA through sharing.
Enable URL Scheme in TrollStore. Install over the existing bundle; do not uninstall.
Android uses a restricted FileProvider and system installer; signing identity
must match the installed app. No release was published during this work.

## Implemented behavior

- Library-first startup; larger listening card, opaque surfaces, 48px primary
  actions, and bounded artwork decoding. No backdrop filters in live screens.
- Background and reduced-effects modes stop the visualizer ticker.
- Music picker connected to Settings and onboarding; accessible library URLs
  export through AVFoundation, and embedded artwork is saved beside the audio.
- Storage screen exports through native Files/SAF pickers.
- Container relocation recovers app-owned paths without losing track metadata;
  reads no longer rewrite away missing entries; manifest writes serialize and
  replace the destination only after the temporary file has flushed.
- GitHub stable release selection, matching platform asset, timed streaming
  download, size and ZIP-header checks, progress, Wi-Fi auto-download preference,
  and platform installer handoff. Music paths and application IDs stay unchanged.
- Existing new-download thumbnails remain enabled; thumbnail requests now timeout.

## Validation constraints

Windows cannot compile the Swift target. Music import, Files export, and TrollStore
replacement must still be verified on the owner's iPhone. Removing GPU work is
verified in code; physical-device heat/battery improvement needs profiling.
Automatic downloads run while Monolith is active; this is not an OS background
transfer service. TrollStore's direct install button downloads through TrollStore;
the locally downloaded IPA is available through Open downloaded IPA.

## Final scope clarification

Owner requires iOS priority and no commits or GitHub pushes. Desktop is deferred:
installed just_audio and on_audio_query packages do not register Windows/Linux
backends. A full-feature process below 150 MB has not been demonstrated. The Pixel
Android debug process measured 247337 KB PSS / 379244 KB RSS; this is diagnostic
only, not a Windows release-memory measurement. The 32 MB image cache cap limits
cached decoded images, not total process memory. Playback progress uses 250–500 ms
intervals. Update downloads flush every 256 KB and reuse a complete cached archive.

The final visual review made the player background opaque, enlarged compact
transport hit areas to 48px, enabled tapping its handle to close, and corrected
singular track counts. No GitHub publication or iOS build was performed.
