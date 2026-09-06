import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../app/state/app_scope.dart';
import '../../core/services/app_update_service.dart';

/// Apple App Store & Apple Music style morphing download indicator.
///
/// Features:
/// - Expanded pill for 2 seconds with 100% centered text.
/// - Smoothly shrinks to a 38x38 circular carrier.
/// - Outer perimeter IS the progress ring (no double outer circle).
/// - Exact Apple HIG centered rounded stop square inside ring.
/// - Transforms into an Apple green checkmark (✓) at 100%.
/// - Dynamically themed to the user's selected accent color from Settings.
class AppDownloadIndicator extends StatefulWidget {
  const AppDownloadIndicator({super.key});

  @override
  State<AppDownloadIndicator> createState() => _AppDownloadIndicatorState();
}

class _AppDownloadIndicatorState extends State<AppDownloadIndicator>
    with SingleTickerProviderStateMixin {
  bool _isPillMode = true;
  Timer? _shrinkTimer;
  Timer? _dismissTimer;
  bool _wasActive = false;
  bool _isComplete = false;

  @override
  void initState() {
    super.initState();
    AppUpdateService.instance.addListener(_onUpdateServiceChanged);
  }

  @override
  void dispose() {
    _shrinkTimer?.cancel();
    _dismissTimer?.cancel();
    AppUpdateService.instance.removeListener(_onUpdateServiceChanged);
    super.dispose();
  }

  void _onUpdateServiceChanged() {
    final service = AppUpdateService.instance;
    final isActive = service.busy && service.progress != null;
    final isDone = service.progress != null && service.progress! >= 1.0;

    if (isActive && !_wasActive) {
      // New download started: show pill for 2 seconds then shrink
      setState(() {
        _isPillMode = true;
        _wasActive = true;
        _isComplete = false;
      });
      _shrinkTimer?.cancel();
      _shrinkTimer = Timer(const Duration(milliseconds: 2000), () {
        if (mounted) setState(() => _isPillMode = false);
      });
    } else if (isDone && !_isComplete) {
      setState(() => _isComplete = true);
      _dismissTimer?.cancel();
      _dismissTimer = Timer(const Duration(milliseconds: 3000), () {
        if (mounted) {
          setState(() {
            _wasActive = false;
            _isComplete = false;
            _isPillMode = true;
          });
        }
      });
    }
  }

  void _toggleMode() {
    setState(() {
      _isPillMode = !_isPillMode;
    });
    if (_isPillMode) {
      _shrinkTimer?.cancel();
      _shrinkTimer = Timer(const Duration(milliseconds: 2500), () {
        if (mounted) setState(() => _isPillMode = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final updateService = AppUpdateService.instance;
    final controller = AppScope.watch(context);
    final isImporting = controller.isImportingAudio;

    final isUpdateDownloading =
        updateService.busy && updateService.progress != null;
    final isActive = isUpdateDownloading || isImporting || _isComplete;

    if (!isActive) {
      return const SizedBox.shrink();
    }

    final double rawProgress = isUpdateDownloading
        ? (updateService.progress ?? 0.0).clamp(0.0, 1.0)
        : (isImporting ? 0.45 : (_isComplete ? 1.0 : 0.0));

    final pctStr = '${(rawProgress * 100).round()}%';
    final titleText = isUpdateDownloading
        ? (_isComplete ? 'Download complete' : 'Downloading update')
        : (isImporting ? 'Importing library' : 'Download complete');
    final subText = isUpdateDownloading
        ? (_isComplete ? 'Ready to install' : 'v${updateService.release?.version ?? '1.4.0'} · $pctStr')
        : (isImporting ? 'Processing audio…' : 'Ready to play');

    final accentColor = Theme.of(context).colorScheme.primary;
    const greenColor = Color(0xFF22C55E);
    final isDone = _isComplete || rawProgress >= 1.0;

    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: GestureDetector(
        onTap: _toggleMode,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
          height: 38,
          width: _isPillMode ? 178 : 38,
          decoration: BoxDecoration(
            color: _isPillMode
                ? const Color(0xFF141924).withValues(alpha: 0.96)
                : const Color(0xFF0D1118),
            borderRadius: BorderRadius.circular(19),
            border: _isPillMode
                ? Border.all(color: Colors.white.withValues(alpha: 0.14))
                : null, // Clean: No extra outer box border in circle mode!
            boxShadow: [
              BoxShadow(
                color: isDone
                    ? greenColor.withValues(alpha: 0.35)
                    : Colors.black.withValues(alpha: 0.5),
                blurRadius: isDone ? 14 : 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(19),
            child: _isPillMode
                // 1) 100% Symmetrically Centered Text Pill
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          titleText,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subText,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: isDone ? greenColor : accentColor,
                            height: 1.15,
                          ),
                        ),
                      ],
                    ),
                  )
                // 2) 38x38 Single Perimeter Circular Carrier (Apple Style 1)
                : SizedBox(
                    width: 38,
                    height: 38,
                    child: CustomPaint(
                      painter: _AppleDownloadRingPainter(
                        progress: rawProgress,
                        trackColor: Colors.white.withValues(alpha: 0.12),
                        progressColor: isDone ? greenColor : accentColor,
                        strokeWidth: 2.8,
                      ),
                      child: Center(
                        child: isDone
                            // Apple Checkmark (✓)
                            ? const Icon(
                                Icons.check_rounded,
                                size: 18,
                                color: greenColor,
                              )
                            // Apple HIG Rounded Stop Square
                            : Container(
                                width: 9,
                                height: 9,
                                decoration: BoxDecoration(
                                  color: accentColor,
                                  borderRadius: BorderRadius.circular(2.2),
                                ),
                              ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// CustomPainter for the perimeter SVG progress ring.
class _AppleDownloadRingPainter extends CustomPainter {
  const _AppleDownloadRingPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
    required this.strokeWidth,
  });

  final double progress;
  final Color trackColor;
  final Color progressColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Track background
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);

    // Progress sweep arc (starts at 12 o'clock, clockwise)
    if (progress > 0) {
      final progressPaint = Paint()
        ..color = progressColor
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = strokeWidth;

      final sweepAngle = 2 * math.pi * progress.clamp(0.0, 1.0);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        sweepAngle,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AppleDownloadRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.progressColor != progressColor ||
        oldDelegate.trackColor != trackColor;
  }
}
