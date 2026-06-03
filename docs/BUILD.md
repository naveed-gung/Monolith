# Building Monolith

## Prerequisites
- Flutter SDK (Dart `^3.10`)
- Android SDK (for APKs); Xcode + CocoaPods on macOS (for iOS)

## Common commands
```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release --no-tree-shake-icons   # Android
flutter build ios  --release --no-codesign           # iOS (macOS only)
```

> `--no-tree-shake-icons` is required because the vendored phosphor patch makes
> icon constructors non-const. iOS release IPAs are built unsigned in CI on `v*` tags.
