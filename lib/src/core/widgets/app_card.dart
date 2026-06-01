import 'package:flutter/material.dart';

import '../../app/theme/design_tokens.dart';

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.color,
    this.borderRadius,
    this.onTap,
    this.elevated = false,
    this.clip = false,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final BorderRadius? borderRadius;
  final VoidCallback? onTap;
  final bool elevated;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final r = borderRadius ?? AppRadii.all(AppRadii.lg);
    final bg = color ??
        (elevated
            ? scheme.surfaceContainerHigh
            : scheme.surfaceContainerLow);

    return ClipRRect(
      borderRadius: r,
      clipBehavior: clip || onTap != null ? Clip.antiAlias : Clip.none,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: r,
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
            width: 0.5,
          ),
          boxShadow: elevated ? AppElevation.card(brightness) : null,
        ),
        child: onTap != null
            ? Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: r,
                  child: Padding(
                    padding: padding ?? const EdgeInsets.all(AppSpacing.lg),
                    child: child,
                  ),
                ),
              )
            : Padding(
                padding: padding ?? const EdgeInsets.all(AppSpacing.lg),
                child: child,
              ),
      ),
    );
  }
}
