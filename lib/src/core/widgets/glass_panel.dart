import 'package:flutter/material.dart';

import '../../app/theme/design_tokens.dart';

class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.borderRadius,
    this.opacity = 0.72,
    this.padding,
    this.reduceEffects = false,
  });

  final Widget child;
  final BorderRadius? borderRadius;
  final double opacity;
  final EdgeInsetsGeometry? padding;

  /// When true, the live backdrop blur is dropped for a flat translucent fill.
  /// Blur readback is the most expensive GPU primitive on older A-series chips,
  /// so callers on a hot path pass the controller's `reduceVisualEffects` here.
  final bool reduceEffects;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = borderRadius ?? AppRadii.all(AppRadii.lg);

    final panel = DecoratedBox(
      decoration: BoxDecoration(
        // A flat fill needs more opacity to read as a panel without the blur
        // doing the visual lifting behind it.
        color: scheme.surfaceContainerLow,
        borderRadius: radius,
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.12),
            blurRadius: 28,
            offset: const Offset(0, AppSpacing.lg),
          ),
        ],
      ),
      child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
    );

    return RepaintBoundary(
      child: ClipRRect(borderRadius: radius, child: panel),
    );
  }
}
