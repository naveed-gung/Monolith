import 'package:flutter/material.dart';

class AlbumArtPainter extends CustomPainter {
  const AlbumArtPainter({required this.colors});

  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final basePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
      ).createShader(rect);

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(28)),
      basePaint,
    );

    final glow = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 26);
    canvas.drawCircle(
      Offset(size.width * 0.24, size.height * 0.20),
      size.width * 0.12,
      glow,
    );

    final ribbon = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.075
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        colors: [
          Colors.white.withValues(alpha: 0.72),
          colors.first.withValues(alpha: 0.48),
          colors[1].withValues(alpha: 0.84),
        ],
      ).createShader(rect);

    for (var i = 0; i < 6; i++) {
      final path = Path()
        ..moveTo(size.width * (0.12 + (i * 0.11)), size.height * 1.02)
        ..cubicTo(
          size.width * (0.24 + (i * 0.05)),
          size.height * 0.62,
          size.width * 0.82,
          size.height * (0.30 + (i * 0.03)),
          size.width * 0.62,
          -size.height * 0.08,
        );
      canvas.drawPath(path, ribbon);
    }

    final accent = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.014
      ..color = Colors.white.withValues(alpha: 0.36);
    canvas.drawCircle(
      Offset(size.width * 0.74, size.height * 0.72),
      size.width * 0.16,
      accent,
    );
    canvas.drawCircle(
      Offset(size.width * 0.74, size.height * 0.72),
      size.width * 0.05,
      Paint()..color = Colors.white.withValues(alpha: 0.68),
    );
  }

  @override
  bool shouldRepaint(covariant AlbumArtPainter oldDelegate) =>
      oldDelegate.colors != colors;
}

class HeroClayPainter extends CustomPainter {
  const HeroClayPainter({required this.colors});

  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final body = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [colors.first, colors[1]],
      ).createShader(rect);

    final shadow = Paint()
      ..color = colors[1].withValues(alpha: 0.14)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30);

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.48, size.height * 0.80),
        width: size.width * 0.62,
        height: size.height * 0.18,
      ),
      shadow,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.16,
          size.height * 0.22,
          size.width * 0.34,
          size.height * 0.42,
        ),
        const Radius.circular(30),
      ),
      body,
    );

    final disc = Paint()
      ..shader = RadialGradient(
        colors: [Colors.white.withValues(alpha: 0.92), colors[2]],
      ).createShader(rect);

    canvas.drawCircle(
      Offset(size.width * 0.68, size.height * 0.36),
      size.width * 0.14,
      disc,
    );

    final stem = Paint()
      ..color = colors[2].withValues(alpha: 0.92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(size.width * 0.74, size.height * 0.18),
      Offset(size.width * 0.74, size.height * 0.56),
      stem,
    );
    canvas.drawLine(
      Offset(size.width * 0.74, size.height * 0.18),
      Offset(size.width * 0.88, size.height * 0.14),
      stem,
    );
    canvas.drawCircle(
      Offset(size.width * 0.69, size.height * 0.58),
      size.width * 0.05,
      Paint()..color = colors[2],
    );
  }

  @override
  bool shouldRepaint(covariant HeroClayPainter oldDelegate) =>
      oldDelegate.colors != colors;
}