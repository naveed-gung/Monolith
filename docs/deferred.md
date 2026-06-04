# Deferred work — exact recipes & why they're not shipped yet

These are genuinely wanted but **cannot be built or verified from the current
Windows dev machine** and each carries real risk to the green release path. They
are documented in full so a Mac/device session can land them quickly. Nothing
half-working is shipped (Task G honesty rule).

## G1 — Real FFT / waveform visualizer

**Today:** the player artwork glow is driven by a synthetic sine "bass" value
(`_ArtworkSection` in `player_page.dart`). It's gated to *player open + playing +
immersive canvas*, capped, quantised, and honours *Reduce visual effects*
(Task H), so it's cheap and cool — just not real audio data.

**Android recipe (native, needs a device):**
1. Add Kotlin using `android.media.audiofx.Visualizer`, attached to
   `just_audio`'s `androidAudioSessionId`.
2. Stream band energy to Dart over an `EventChannel`; configure it in
   `MainActivity.configureFlutterEngine`.
3. On the Dart side, feed it into a `ValueNotifier<double>` and drive the glow
   from that instead of the sine wave; keep the existing gating + `RepaintBoundary`
   so the heat fix is preserved.

**Why deferred / the catch:** `Visualizer` requires the
**`RECORD_AUDIO`** permission (plus `MODIFY_AUDIO_SETTINGS`). Adding a
microphone-class permission to a music player is a real privacy/UX decision the
owner should sign off on, and the whole path can only be verified by *hearing
and seeing it react on a device*. Shipping untested native effect code (which can
throw on attach for some OEMs) into a green release is exactly the blind-merge
risk we avoid.

**iOS recipe (needs a Mac):** `MTAudioProcessingTap` on the AVPlayer mix +
`vDSP` FFT, and it must coexist with `just_audio` without double-playback. Stub
the channel; keep the sine fallback on iOS.

## G2 — Per-accent launcher icons

**Today:** one fixed coral **m** launcher icon. The *in-app* "m" already follows
the accent (shipped 1.0.3). Home-screen icon does not change.

**Android recipe (native, needs a device):**
1. Generate per-accent mipmap sets from `branding/gen_icon.py` (asset-only, safe).
2. Add an `activity-alias` per accent in `AndroidManifest.xml`, each pointing at
   its mipmap, all but the default disabled.
3. Add `flutter_dynamic_icon_plus` and an explicit **"App icon"** picker in
   Settings (NOT auto-tied to the accent — switching shows churn).

**Why deferred:** a wrong `activity-alias` configuration can **remove the app
from the launcher** entirely, and alias/icon switching only manifests on a real
device — unverifiable from Windows. A dead picker (UI with no working backend)
is worse than no picker, so the Settings entry waits until the native side is
proven.

**iOS recipe (needs a Mac):** bake `CFBundleAlternateIcons` + PNG sets into
`ios/Runner`; swapping triggers an **unavoidable iOS system alert**. Prepare the
plist but leave it disabled until it can be built on a Mac.

---

**Summary:** G1 and G2 are both **deferred on both platforms** — Android halves
need a device (and G1 needs a `RECORD_AUDIO` decision), iOS halves need a Mac.
The current visuals are correct and cool; these add fidelity, not function.
