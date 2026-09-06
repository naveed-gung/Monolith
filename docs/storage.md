# Music storage, updates, and backups

## Owned files

- **iOS:** the app Documents directory, then `Monolith/Music`. Imports use `Monolith/Music/Imports`.
- **Android:** the app external files directory, then `Monolith/Music`; imported copies use its `Imports` subfolder.
- `Monolith/manifest.json` stores track metadata. Artwork is kept beside audio when available.
- Temporary downloads end in `.part` and are excluded from library scans.

On iOS, browse Files → On My iPhone → Monolith → Monolith → Music. The first Monolith is the app's Documents entry; the second is the folder created by the store.

## Removing the originals from Apple Music

A successful Music import produces a separate audio file in Monolith. A readable file URL is copied; a library asset is exported by AVFoundation. Monolith subsequently plays its own file, so deleting the original song or the Music app should not delete that copy.

Before removing originals, verify **every song you need**, especially imports from a build that showed “Cannot Open”:

1. Confirm it appears in Monolith with a duration.
2. Close and reopen Monolith, then play it in airplane mode.
3. Export a backup outside Monolith, such as a computer or a separate Files location.

A duration alone does not prove that an entire file decodes correctly. Files reported as failed, unavailable, or protected were not successfully copied. Protected Apple Music subscription assets are not converted into unrestricted audio by TrollStore or a jailbreak.

Deleting Music can affect Apple's Music-library integrations and future imports. See Apple's [built-in app deletion guidance](https://support.apple.com/en-nz/101264). It is different from deleting Monolith.

## Updating Monolith

Install the replacement build over the existing app, using the same app identity. On iOS, use the intended TrollStore replacement flow; on Android, use a compatible signing key. Updates are stored in cache, separately from music. The loader repairs paths if an iOS app container moves.

No installation flow can promise recovery after the user deletes the app or its data. Keep a separate backup before replacing a build containing valuable music.

## Deleting Monolith

Treat Monolith's app storage as removable with the app. Do not rely on app-private Documents or Android app external files surviving uninstall.

Use the export action to make copies outside the app first. The repository has native Files/SAF export and a public-Music writing bridge, but the active download path still defaults to the app's own music folder. Automatic iCloud backup/sync is not implemented.

## Recovery behavior

The loader accepts legacy and schema-v2 manifests, rebinds moved paths, and merges surviving audio. It recognizes `Imports` as imported music and reads missing durations without starting playback. Missing files are excluded from the visible snapshot; the read path does not deliberately prune their manifest records. A later explicit save can persist the visible collection, so the manifest is not a substitute for a backup.

Imported songs appear in Library and Songs. Downloads lists only records with `source=downloaded`. Storage management includes all owned audio, irrespective of source.
