import 'package:flutter/material.dart';

import 'design_tokens.dart';

class MonolithTheme {
  MonolithTheme._();

  static ThemeData light(AccentSwatch accent) =>
      _build(Brightness.light, accent);

  static ThemeData dark(AccentSwatch accent) =>
      _build(Brightness.dark, accent);

  static ThemeData _build(Brightness brightness, AccentSwatch accent) {
    final s = brightness == Brightness.light
        ? AppSurfaces.light
        : AppSurfaces.dark;
    final isLight = brightness == Brightness.light;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: accent.base,
      onPrimary: accent.on,
      primaryContainer: accent.base.withValues(alpha: isLight ? 0.12 : 0.22),
      onPrimaryContainer: accent.base,
      secondary: accent.base,
      onSecondary: accent.on,
      secondaryContainer: s.surfaceHigh,
      onSecondaryContainer: s.textPrimary,
      tertiary: accent.base,
      onTertiary: accent.on,
      tertiaryContainer: s.surfaceHigher,
      onTertiaryContainer: s.textPrimary,
      error: isLight ? const Color(0xFFB3261E) : const Color(0xFFCF6679),
      onError: isLight ? const Color(0xFFFFFFFF) : const Color(0xFF370009),
      errorContainer: isLight ? const Color(0xFFF9DEDC) : const Color(0xFF93000A),
      onErrorContainer: isLight ? const Color(0xFF410E0B) : const Color(0xFFFFDAD6),
      surface: s.canvas,
      onSurface: s.textPrimary,
      surfaceContainerLowest: s.canvas,
      surfaceContainerLow: s.surface,
      surfaceContainer: s.surfaceHigh,
      surfaceContainerHigh: s.surfaceHigher,
      surfaceContainerHighest: s.border,
      onSurfaceVariant: s.textSecondary,
      outline: s.border,
      outlineVariant: s.border.withValues(alpha: 0.65),
      shadow: const Color(0xFF000000),
      scrim: const Color(0xFF000000),
      inverseSurface: isLight ? AppSurfaces.dark.canvas : AppSurfaces.light.canvas,
      onInverseSurface: isLight ? AppSurfaces.dark.textPrimary : AppSurfaces.light.textPrimary,
      inversePrimary: accent.base,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
    );

    final textTheme = base.textTheme.copyWith(
      displaySmall: base.textTheme.displaySmall?.copyWith(
        fontWeight: AppType.display,
        letterSpacing: AppType.trackTight,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontWeight: AppType.display,
        letterSpacing: AppType.trackTight,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: AppType.title,
        letterSpacing: AppType.trackSnug,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: AppType.title,
        letterSpacing: AppType.trackSnug,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(
        fontWeight: AppType.body,
        letterSpacing: AppType.trackNormal,
        height: 1.35,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        fontWeight: AppType.body,
        letterSpacing: AppType.trackNormal,
        height: 1.35,
      ),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontWeight: AppType.label,
        letterSpacing: AppType.trackWide,
      ),
    );

    return base.copyWith(
      scaffoldBackgroundColor: s.canvas,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: textTheme.titleLarge?.copyWith(color: s.textPrimary),
        iconTheme: IconThemeData(color: s.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: s.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.all(AppRadii.lg),
          side: BorderSide(color: s.border, width: 0.5),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent.base,
          foregroundColor: accent.on,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: AppRadii.all(AppRadii.md),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: s.textPrimary,
          side: BorderSide(color: s.border),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: AppRadii.all(AppRadii.md),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: s.surface,
        border: OutlineInputBorder(
          borderSide: BorderSide(color: s.border, width: 0.5),
          borderRadius: AppRadii.all(AppRadii.md),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: s.border, width: 0.5),
          borderRadius: AppRadii.all(AppRadii.md),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: accent.base, width: 1.5),
          borderRadius: AppRadii.all(AppRadii.md),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        hintStyle: TextStyle(color: s.textTertiary),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: accent.base.withValues(alpha: 0.18),
        indicatorShape: const StadiumBorder(),
        labelTextStyle: WidgetStatePropertyAll(
          textTheme.labelMedium?.copyWith(
            fontWeight: AppType.label,
            letterSpacing: AppType.trackWide,
          ),
        ),
        iconTheme: WidgetStatePropertyAll(
          IconThemeData(color: s.textSecondary, size: 26),
        ),
      ),
      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: accent.base,
        inactiveTrackColor: s.surfaceHigher,
        thumbColor: accent.base,
        overlayColor: accent.base.withValues(alpha: 0.14),
        trackHeight: 3,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: s.surfaceHigh,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: s.textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.all(AppRadii.sm),
          side: BorderSide(color: s.border, width: 0.5),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: s.border,
        thickness: 0.5,
        space: 0,
      ),
      listTileTheme: ListTileThemeData(
        tileColor: Colors.transparent,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.all(AppRadii.sm),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return accent.base.withValues(alpha: 0.18);
            }
            return Colors.transparent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return accent.base;
            return s.textSecondary;
          }),
          side: WidgetStatePropertyAll(
            BorderSide(color: s.border, width: 0.5),
          ),
          textStyle: WidgetStatePropertyAll(
            textTheme.labelMedium?.copyWith(fontWeight: AppType.label),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: s.textPrimary),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accent.on;
          return s.textTertiary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accent.base;
          return s.surfaceHigher;
        }),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accent.base;
          return Colors.transparent;
        }),
        checkColor: WidgetStatePropertyAll(accent.on),
        side: BorderSide(color: s.border, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: ZoomPageTransitionsBuilder(),
        },
      ),
    );
  }
}
