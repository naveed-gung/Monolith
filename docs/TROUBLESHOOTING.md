# Troubleshooting

### A downloaded track plays silently / shows 00:00 (iOS)
Fixed in 1.0.2 — the audio session is configured at startup. Update to the latest build.

### Downloaded tracks disappeared
Missing files are pruned from the manifest on load. On iOS the music lives in
**On My iPhone › Monolith › Music** (Files app).

### Android build behaves oddly after dependency changes
Re-run `flutter pub get` and check the vendored overrides under `third_party/`.

### Lock screen / notification controls missing
Confirm a track with a valid local path is playing; on iOS use Lock Screen / Control Center.
