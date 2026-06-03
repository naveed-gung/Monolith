# Sideloading Monolith on iOS

The iOS build is an **unsigned IPA**. Options:

## AltStore / Sideloadly
Install with your own Apple ID. Free accounts must re-sign every 7 days.

## TrollStore (recommended where supported)
On a jailbroken device, install `monolith.ipa` permanently with
[TrollStore](https://github.com/opa334/TrollStore) — no re-sign, no computer.

## TrollStore Lite
On **iOS 16.7.x**, use TrollStore Lite to install the same IPA permanently.

## Re-sign in Xcode
Open the IPA's app in Xcode and sign with your own Apple ID / team.
