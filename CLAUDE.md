# CLAUDE.md — Monolith

Offline-first Flutter music player (Android + iOS). Controller-driven, feature-scoped.
This file is your standing context. Obey it on every task. Do not re-derive it.

---

## CURRENT GOAL: full UI/UX rework

Direction: **"Spotify bones, Apple skin."**
- Spotify = structure: near-black dense dark theme, card/grid library, horizontal
  shelves, persistent mini-player docked above the tab bar.
- Apple = skin + motion: airy warm-white light theme, album-art color bleed behind
  the now-playing screen, calm and *consistent* transitions, Hero artwork flights.

We are reskinning the **presentation + theme layer only**. The architecture is good.

---

## HARD RULES (non-negotiable)

1. **NEVER edit `lib/src/app/state/app_controller.dart` for visual work.** It owns
   all state (playback, downloads, queue, playlists, nav, theme). Visual changes go
   in `theme/`, `core/widgets/`, and `features/*/presentation/`. The ONLY allowed
   controller change in this rework is adding accent-preset state (see THEMING).
2. **All visual values come from `lib/src/app/theme/design_tokens.dart`.**
   - No `Color(0x...)` literals in widgets. Use `AppSurfaces` / `AccentSwatch`.
   - No raw padding/radius numbers. Use `AppSpacing` / `AppRadii`.
   - No `Curves.*` / `Duration(...)` literals in widgets. Use `AppMotion`.
3. **No `ColorScheme.fromSeed` for surfaces.** Surfaces are defined explicitly in
   tokens. `fromSeed` is what made the old UI muddy.
4. **Cross-platform: identical on Android & iOS.** Drop all `.adaptive` widgets
   (`SwitchListTile.adaptive`, etc.) in favor of custom widgets that render the same
   on both. Platform-specific code is allowed ONLY in system integration
   (media notifications, lock screen, Control Center) — not in UI chrome.
5. **Motion must be consistent.** Default screen/element transitions:
   `AppMotion.durMedium` + `AppMotion.standard`. Player sheet open/Hero:
   `AppMotion.emphasized`. Things leaving: `AppMotion.exit`. No one-off curves.

---

## ICONS — replace stock Material icons

The old `Icons.library_music_outlined` / `Icons.download` set is the #1 "beginner"
tell. Use **`phosphor_flutter`** (SF-Symbols-like, has weight variants).

- Install: `flutter pub add phosphor_flutter`
- Nav pattern (Spotify/Apple): **regular/thin weight when unselected, fill or bold
  when selected.** e.g. `PhosphorIcons.house()` vs `PhosphorIcons.house(PhosphorIconsStyle.fill)`.
- Standard sizes: nav 26, inline 20, transport (play/skip) 28–32, hero play 40.
- Keep icon usage centralized — define an `AppIcons` map in
  `lib/src/core/widgets/app_icons.dart` so swaps are one-file changes.
- Do NOT mix Material `Icons.*` and Phosphor in the same screen.

---

## THEMING — user-adjustable accent + light/dark/system

Existing: `enum ThemePreference { system, light, dark }`, controller has
`themePreference` / `setThemePreference`, Settings has a SegmentedButton. Keep that.

ADD accent selection:
- Controller holds `AccentPreset accentPreset` (default `AccentSwatch.fallback`),
  with `setAccentPreset(AccentPreset)` that `notifyListeners()` and persists it
  (same persistence path as other prefs).
- Theme builder signature becomes:
  `MonolithTheme.build(Brightness brightness, AccentSwatch accent)`
  with `static ThemeData light(AccentSwatch a)` / `dark(AccentSwatch a)` helpers.
- `MonolithApp` passes `AccentSwatch.of(controller.accentPreset)` into both themes.
- Settings shows a row of accent swatches (`AccentSwatch.all`) the user taps to pick.
- Accent applies in BOTH light and dark; surfaces switch with brightness.

---

## ARCHITECTURE MAP (so you read the right file, not the whole repo)

```
lib/src/
  app/
    monolith_app.dart            # MaterialApp, passes theme + accent
    state/app_controller.dart    # STATE — do not touch for visuals (except accent)
    state/app_scope.dart         # AppScope.watch/read(context)
    theme/design_tokens.dart     # tokens (source of truth)
    theme/monolith_theme.dart    # builds ThemeData from tokens + accent
  core/
    models/music_models.dart     # Track, enums (AppTab, ThemePreference, ...)
    widgets/                     # glass_panel, track_artwork, section_header,
                                 #   atmosphere, app_header, app_icons (new)
  features/*/presentation/       # library, downloads, player, search, settings, shell
```

State access: `final controller = AppScope.watch(context);` (read for callbacks).

---

## REWORK PHASES (one phase per session; `/clear` between them)

- **P1 Theme:** rewrite `monolith_theme.dart` to consume tokens + accent. No fromSeed surfaces.
- **P2 Core widgets:** `app_icons.dart`, `glass_panel`, `track_artwork`, `section_header`,
  new `app_button`, `app_toggle`, `mini_player`. (Reused everywhere → highest leverage.)
- **P3 Shell + nav + motion:** `music_shell.dart`. New tab model (Home/Search/Library;
  Downloads folds into Library; Settings → profile sheet). Shared page transitions.
  Hero artwork mini→full. Spring-physics player sheet. (Use plan mode first.)
- **P4 Per-screen:** library → player → search → downloads → settings. One screen / session.

---

## WORKFLOW (keep token cost low)

- I will name the exact file(s) to edit. **Read only those files.** Do not scan the repo.
- Don't re-read `design_tokens.dart` once you know it — its API is summarized above.
- After edits, I verify with `flutter analyze` (and `flutter test test/widget_test.dart`).
  Don't re-read files to "double check"; trust analyze.
- Prefer surgical edits over full-file rewrites unless the file is being redesigned.
- Ask before adding any dependency other than `phosphor_flutter`.

---

## VERIFY

```sh
flutter pub get
flutter analyze
flutter test test/widget_test.dart
```
