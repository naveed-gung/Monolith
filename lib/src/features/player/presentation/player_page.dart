import 'dart:math' as math;

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app/state/app_controller.dart';
import '../../../app/state/app_scope.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../core/models/music_models.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/track_artwork.dart';

class PlayerPage extends StatelessWidget {
  const PlayerPage({
    super.key,
    required this.animation,
    required this.artworkAnimation,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.screenInset,
      AppSpacing.sm,
      AppSpacing.screenInset,
      AppSpacing.xxxl,
    ),
  });

  final Animation<double> animation;
  final Animation<double> artworkAnimation;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.watch(context);

    if (controller.currentTrack == null) {
      return Center(
        child: Padding(
          padding: padding,
          child: Text(
            'Nothing playing',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      );
    }

    return ListView(
      padding: padding,
      physics: const BouncingScrollPhysics(),
      children: [
        _ArtworkSection(
          controller: controller,
          animation: animation,
          artworkAnimation: artworkAnimation,
        ),
        const SizedBox(height: AppSpacing.xxl),
        _TrackInfo(controller: controller),
        const SizedBox(height: AppSpacing.xl),
        _ProgressSection(controller: controller),
        const SizedBox(height: AppSpacing.xl),
        _TransportControls(controller: controller),
        const SizedBox(height: AppSpacing.xxxl),
        _UpNextSection(controller: controller),
      ],
    );
  }

  static String formatDuration(Duration duration) {
    final m = duration.inMinutes;
    final s = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

// ── Artwork ────────────────────────────────────────────────────────────────

class _ArtworkSection extends StatelessWidget {
  const _ArtworkSection({
    required this.controller,
    required this.animation,
    required this.artworkAnimation,
  });

  final MonolithController controller;
  final Animation<double> animation; // visualizer (fast) — drives bass glow
  final Animation<double> artworkAnimation; // slow rotation (unused now)

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final track = controller.currentTrack!;
    final maxSize = math.min(
      MediaQuery.sizeOf(context).width - AppSpacing.screenInset * 2,
      360.0,
    );

    // Play/pause scale handled here — NOT bass-driven.
    return Center(
      child: AnimatedScale(
        scale: controller.isPlaying ? 1.0 : 0.94,
        duration: AppMotion.durMedium,
        curve: AppMotion.standard,
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: animation,
            builder: (context, child) {
              final t = animation.value;
              // Immersive canvas drives the reactive pulse. When it's off the
              // glow stays calm and static instead of breathing with the bass.
              final bass = (controller.isPlaying && controller.immersiveCanvas)
                  ? ((math.sin(t * math.pi * 2) *
                              math.sin(t * math.pi * 3.1) *
                              0.6 +
                          math.sin(t * math.pi * 5.7).abs() * 0.4)
                      .abs()
                      .clamp(0.0, 1.0))
                  : 0.0;

              // Only the glow pulses — image/thumbnail stays at fixed size.
              // Kept deliberately modest: a big animated blur re-rasterises the
              // shadow every frame (heavy on 120Hz panels), so the ceiling is
              // capped to stay smooth and cool.
              final glowRadius = 24 + bass * 30;
              final glowAlpha = 0.16 + bass * 0.28;

              return Container(
                width: maxSize,
                height: maxSize,
                decoration: BoxDecoration(
                  borderRadius: AppRadii.all(AppRadii.xl),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: glowAlpha),
                      blurRadius: glowRadius,
                      spreadRadius: bass * 3,
                      offset: const Offset(0, 16),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: child,
              );
            },
            child: Hero(
              tag: 'player-artwork-${track.id}',
              child: ClipRRect(
                borderRadius: AppRadii.all(AppRadii.xl),
                child: TrackArtwork(
                  track: track,
                  borderRadius: AppRadii.all(AppRadii.xl),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Track info ─────────────────────────────────────────────────────────────

class _TrackInfo extends StatelessWidget {
  const _TrackInfo({required this.controller});
  final MonolithController controller;

  @override
  Widget build(BuildContext context) {
    final track = controller.currentTrack!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.headlineMedium?.copyWith(
                      fontWeight: AppType.title,
                      letterSpacing: AppType.trackTight,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: AppType.body,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            _SourceBadge(source: track.source),
          ],
        ),
      ],
    );
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.source});
  final TrackSource source;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = switch (source) {
      TrackSource.mock => 'Demo',
      TrackSource.device => 'Library',
      TrackSource.downloaded => 'Downloaded',
      TrackSource.imported => 'Imported',
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: AppRadii.all(AppRadii.pill),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
          width: 0.5,
        ),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: AppType.label,
              letterSpacing: AppType.trackWide,
            ),
      ),
    );
  }
}

// ── Progress ───────────────────────────────────────────────────────────────

class _ProgressSection extends StatelessWidget {
  const _ProgressSection({required this.controller});
  final MonolithController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final total = PlayerPage.formatDuration(controller.currentTrackDuration);
    final timeStyle = textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontWeight: AppType.body,
    );

    return Column(
      children: [
        // Seek bar driven by the progress notifier so it repaints in isolation
        // (no per-tick shell rebuild).
        RepaintBoundary(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
              activeTrackColor: scheme.primary,
              inactiveTrackColor: scheme.outlineVariant.withValues(alpha: 0.5),
              thumbColor: Colors.white,
              overlayColor: scheme.primary.withValues(alpha: 0.16),
            ),
            child: ValueListenableBuilder<double>(
              valueListenable: controller.progress,
              builder: (_, value, _) => Slider(
                value: value,
                onChanged: controller.setPlaybackProgress,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              RepaintBoundary(
                child: ValueListenableBuilder<Duration>(
                  valueListenable: controller.positionListenable,
                  builder: (_, pos, _) => Text(
                    PlayerPage.formatDuration(pos),
                    style: timeStyle,
                  ),
                ),
              ),
              Text(total, style: timeStyle),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Transport ──────────────────────────────────────────────────────────────

class _TransportControls extends StatelessWidget {
  const _TransportControls({required this.controller});
  final MonolithController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final track = controller.currentTrack!;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Shuffle
          _ToggleButton(
            key: const Key('player-shuffle'),
            icon: controller.shuffleEnabled
                ? AppIcons.shuffleFill
                : AppIcons.shuffle,
            active: controller.shuffleEnabled,
            onPressed: controller.toggleShuffle,
            tooltip: 'Shuffle',
          ),
          // Previous
          _TransportButton(
            key: const Key('player-prev'),
            icon: AppIcons.skipBack,
            onPressed: controller.previousTrack,
            size: 28,
            tooltip: 'Previous',
          ),
          // Play / pause (large)
          GestureDetector(
            key: const Key('player-play-toggle'),
            onTap: track.canPlay ? controller.togglePlayback : null,
            child: AnimatedContainer(
              duration: AppMotion.durFast,
              curve: AppMotion.standard,
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: scheme.primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.36),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Center(
                child: PhosphorIcon(
                  controller.isPlaying ? AppIcons.pause : AppIcons.play,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ),
          // Next
          _TransportButton(
            key: const Key('playback-next'),
            icon: AppIcons.skipForward,
            onPressed: () => controller.nextTrack(openPlayer: true),
            size: 28,
            tooltip: 'Next',
          ),
          // Repeat
          _ToggleButton(
            key: const Key('player-repeat'),
            icon: _repeatIcon(controller.repeatMode),
            active: controller.repeatMode != RepeatMode.off,
            onPressed: controller.cycleRepeatMode,
            tooltip: 'Repeat',
          ),
        ],
      ),
    );
  }

  static PhosphorIconData _repeatIcon(RepeatMode mode) => switch (mode) {
        RepeatMode.off => AppIcons.repeat,
        RepeatMode.all => AppIcons.repeatFill,
        RepeatMode.one => AppIcons.repeatOne,
      };
}

class _TransportButton extends StatelessWidget {
  const _TransportButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.size,
    required this.tooltip,
  });

  final PhosphorIconData icon;
  final VoidCallback? onPressed;
  final double size;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      onPressed: onPressed,
      icon: PhosphorIcon(icon, size: size),
      color: scheme.onSurface,
      tooltip: tooltip,
      padding: const EdgeInsets.all(AppSpacing.sm),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  const _ToggleButton({
    super.key,
    required this.icon,
    required this.active,
    required this.onPressed,
    required this.tooltip,
  });

  final PhosphorIconData icon;
  final bool active;
  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      onPressed: onPressed,
      icon: PhosphorIcon(icon, size: 22),
      color: active ? scheme.primary : scheme.onSurfaceVariant,
      tooltip: tooltip,
      padding: const EdgeInsets.all(AppSpacing.sm),
    );
  }
}

// ── Up Next ────────────────────────────────────────────────────────────────

class _UpNextSection extends StatelessWidget {
  const _UpNextSection({required this.controller});
  final MonolithController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Up Next',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: AppType.title,
                  letterSpacing: AppType.trackSnug,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (controller.upNextTracks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Text(
              'End of queue',
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final track in controller.upNextTracks) ...[
            _QueueTile(track: track),
            Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ],
      ],
    );
  }
}

class _QueueTile extends StatelessWidget {
  const _QueueTile({required this.track});
  final Track track;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.read(context);
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () => controller.selectTrack(track, openPlayer: true),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: TrackArtwork(
                track: track,
                borderRadius: AppRadii.all(AppRadii.sm),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: AppType.label,
                        ),
                  ),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            PhosphorIcon(
              AppIcons.caretRight,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
