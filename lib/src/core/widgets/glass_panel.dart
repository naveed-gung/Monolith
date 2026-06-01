import 'dart:ui';

import 'package:flutter/material.dart';

import '../../app/theme/design_tokens.dart';

class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.borderRadius,
    this.opacity = 0.72,
    this.padding,
  });

  final Widget child;
  final BorderRadius? borderRadius;
  final double opacity;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = borderRadius ?? AppRadii.all(AppRadii.lg);
    final surfaceColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.black
        : Colors.white;

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: surfaceColor.withValues(alpha: opacity),
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
          child: Padding(
            padding: padding ?? EdgeInsets.zero,
            child: child,
          ),
        ),
      ),
    );
  }
}
