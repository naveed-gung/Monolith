import 'package:flutter/material.dart';

class Atmosphere extends StatelessWidget {
  const Atmosphere({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer.withValues(alpha: 0.18),
            scheme.surface,
            scheme.tertiary.withValues(alpha: 0.08),
          ],
          stops: const [0, 0.55, 1],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -120,
            left: -60,
            child: _GlowOrb(
              size: 280,
              color: scheme.primary.withValues(alpha: 0.20),
            ),
          ),
          Positioned(
            top: 120,
            right: -80,
            child: _GlowOrb(
              size: 220,
              color: scheme.secondary.withValues(alpha: 0.18),
            ),
          ),
          Positioned(
            bottom: -80,
            left: 80,
            child: _GlowOrb(
              size: 200,
              color: scheme.tertiary.withValues(alpha: 0.14),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}
