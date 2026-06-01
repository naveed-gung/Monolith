// lib/src/app/theme/design_tokens.dart
//
// SINGLE SOURCE OF TRUTH for Monolith's visual system.
// Direction: "Spotify bones, Apple skin" — near-black dense dark theme,
// airy warm-white light theme, one user-selectable accent, calm consistent motion.
//
// RULES (enforced in CLAUDE.md):
//  - Every color/spacing/radius/duration/curve in the app comes from here.
//  - No ColorScheme.fromSeed for surfaces. Surfaces are defined explicitly below.
//  - No hard-coded Color(0x...), magic numbers, or Curves.* literals in widgets.
//  - Identical on Android & iOS. Platform differences live ONLY in system
//    integration (media notifications / lock screen / Control Center).

import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────
// SURFACES — explicit, designed steps. (Material's auto-generated surface
// containers are what made the old UI look muddy. We define every step.)
// ─────────────────────────────────────────────────────────────────────────

class AppSurfaces {
  const AppSurfaces({
    required this.canvas, // app background (deepest)
    required this.surface, // default card / panel
    required this.surfaceHigh, // raised card, sheets
    required this.surfaceHigher, // hover / pressed / nav indicator
    required this.border, // hairline dividers & outlines
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary, // captions, disabled-ish
  });

  final Color canvas;
  final Color surface;
  final Color surfaceHigh;
  final Color surfaceHigher;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  // Spotify-ish near-black. Steps are subtle on purpose — premium = restraint.
  static const dark = AppSurfaces(
    canvas: Color(0xFF0A0A0C),
    surface: Color(0xFF121214),
    surfaceHigh: Color(0xFF1B1B1F),
    surfaceHigher: Color(0xFF26262C),
    border: Color(0xFF2C2C33),
    textPrimary: Color(0xFFF5F5F7),
    textSecondary: Color(0xFFA2A2AC),
    textTertiary: Color(0xFF6C6C76),
  );

  // Apple-ish warm near-white. NOT pure white — pure white reads cheap.
  static const light = AppSurfaces(
    canvas: Color(0xFFFAFAFB),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFF1F1F4),
    surfaceHigher: Color(0xFFE7E7EC),
    border: Color(0xFFDDDDE3),
    textPrimary: Color(0xFF0B0B0F),
    textSecondary: Color(0xFF5C5C66),
    textTertiary: Color(0xFF9A9AA4),
  );
}

// ─────────────────────────────────────────────────────────────────────────
// ACCENT — user-selectable in Settings. Persisted by the controller and fed
// into MonolithTheme.build(brightness, accent). `on` is the text/icon color
// that sits ON TOP of the accent (chosen per-swatch for contrast, not auto).
// ─────────────────────────────────────────────────────────────────────────

enum AccentPreset { coral, violet, ocean, lime, amber, magenta }

class AccentSwatch {
  const AccentSwatch({
    required this.preset,
    required this.label,
    required this.base,
    required this.on,
  });

  final AccentPreset preset;
  final String label; // shown in Settings
  final Color base; // the accent itself
  final Color on; // text/icon drawn over `base`

  static const _table = <AccentPreset, AccentSwatch>{
    // Default. Apple-Music energy without copying its exact pink.
    AccentPreset.coral: AccentSwatch(
      preset: AccentPreset.coral,
      label: 'Coral',
      base: Color(0xFFFF4D5E),
      on: Color(0xFFFFFFFF),
    ),
    AccentPreset.violet: AccentSwatch(
      preset: AccentPreset.violet,
      label: 'Violet',
      base: Color(0xFF8B5CF6),
      on: Color(0xFFFFFFFF),
    ),
    // Brightened evolution of the old 0xFF0D6E6E brand teal — keeps identity.
    AccentPreset.ocean: AccentSwatch(
      preset: AccentPreset.ocean,
      label: 'Ocean',
      base: Color(0xFF1FC8C0),
      on: Color(0xFF04201F),
    ),
    AccentPreset.lime: AccentSwatch(
      preset: AccentPreset.lime,
      label: 'Lime',
      base: Color(0xFF38D66B),
      on: Color(0xFF05210F),
    ),
    AccentPreset.amber: AccentSwatch(
      preset: AccentPreset.amber,
      label: 'Amber',
      base: Color(0xFFFFB020),
      on: Color(0xFF241600),
    ),
    AccentPreset.magenta: AccentSwatch(
      preset: AccentPreset.magenta,
      label: 'Magenta',
      base: Color(0xFFFF3D9A),
      on: Color(0xFFFFFFFF),
    ),
  };

  static AccentSwatch of(AccentPreset preset) => _table[preset]!;

  static const AccentPreset fallback = AccentPreset.coral;

  static List<AccentSwatch> get all => AccentPreset.values
      .map((preset) => _table[preset]!)
      .toList(growable: false);
}

// ─────────────────────────────────────────────────────────────────────────
// SPACING — 4pt base scale. Use these names, never raw numbers in padding.
// ─────────────────────────────────────────────────────────────────────────

class AppSpacing {
  const AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  // Common layout constants
  static const double screenInset = 20; // left/right page padding
  static const double navHeight = 64; // bottom tab bar
  static const double miniPlayerHeight = 64;
}

// ─────────────────────────────────────────────────────────────────────────
// RADII — pill nav indicator, rounded cards, full-round for avatars/FAB.
// ─────────────────────────────────────────────────────────────────────────

class AppRadii {
  const AppRadii._();
  static const double sm = 12; // chips, small controls
  static const double md = 18; // buttons, inputs, list tiles
  static const double lg = 24; // cards, sheets, artwork
  static const double xl = 32; // hero / now-playing artwork
  static const double pill = 999;

  static BorderRadius all(double r) => BorderRadius.circular(r);
}

// ─────────────────────────────────────────────────────────────────────────
// MOTION — the heart of the "Apple polish". EVERY transition uses these.
// Consistency is what separates premium from beta. Pick from this list only.
// ─────────────────────────────────────────────────────────────────────────

class AppMotion {
  const AppMotion._();

  // Durations
  static const Duration durFast = Duration(milliseconds: 180); // taps, toggles
  static const Duration durMedium = Duration(milliseconds: 320); // screen swaps
  static const Duration durSlow = Duration(milliseconds: 460); // player sheet

  // Curves
  static const Curve standard = Curves.easeOutCubic; // default for everything
  static const Curve emphasized = Cubic(0.2, 0.0, 0.0, 1.0); // hero / sheet open
  static const Curve exit = Curves.easeInCubic; // things leaving

  // Spring (for the draggable now-playing sheet). Use with SpringSimulation
  // or flutter_animate / a physics-based AnimationController.
  static const double springStiffness = 380;
  static const double springDamping = 28;
}

// ─────────────────────────────────────────────────────────────────────────
// ELEVATION — soft, low, single-direction shadows. No Material drop-shadow
// stacking. Dark theme barely uses shadow (depth comes from surface steps).
// ─────────────────────────────────────────────────────────────────────────

class AppElevation {
  const AppElevation._();

  static List<BoxShadow> card(Brightness brightness) {
    if (brightness == Brightness.dark) {
      return const [
        BoxShadow(
          color: Color(0x40000000),
          blurRadius: 24,
          offset: Offset(0, 8),
        ),
      ];
    }
    return const [
      BoxShadow(
        color: Color(0x14000000),
        blurRadius: 20,
        offset: Offset(0, 6),
      ),
    ];
  }

  static List<BoxShadow> sheet(Brightness brightness) {
    final opacity = brightness == Brightness.dark ? 0x66 : 0x1F;
    return [
      BoxShadow(
        color: Color(opacity << 24),
        blurRadius: 40,
        offset: const Offset(0, -10),
      ),
    ];
  }
}

// ─────────────────────────────────────────────────────────────────────────
// TYPOGRAPHY SCALE — weights/letter-spacing only (font family set in theme).
// Tight tracking on big text = the Apple display look.
// ─────────────────────────────────────────────────────────────────────────

class AppType {
  const AppType._();
  // letter spacing
  static const double trackTight = -0.8; // display / headline
  static const double trackSnug = -0.3; // titles
  static const double trackNormal = 0.0; // body
  static const double trackWide = 0.4; // labels / overlines

  // weights
  static const FontWeight display = FontWeight.w800;
  static const FontWeight title = FontWeight.w700;
  static const FontWeight body = FontWeight.w500;
  static const FontWeight label = FontWeight.w600;
}
