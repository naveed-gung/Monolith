import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/state/app_controller.dart';
import '../../../app/state/app_scope.dart';
import '../../../core/models/music_models.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/track_artwork.dart';

class PlayerPage extends StatelessWidget {
  const PlayerPage({
    super.key,
    required this.animation,
    required this.artworkAnimation,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 132),
  });

  final Animation<double> animation;
  final Animation<double> artworkAnimation;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.watch(context);
    final textTheme = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final deckWidth = math.max(0.0, math.min(availableWidth - 40, 420.0));

        return ListView(
          padding: padding,
          children: [
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: deckWidth),
                child: _PlaybackDeck(
                  controller: controller,
                  animation: animation,
                  artworkAnimation: artworkAnimation,
                  availableWidth: availableWidth,
                ),
              ),
            ),
            const SizedBox(height: 28),
            SectionHeader(
              title: 'Next songs',
              actionLabel: 'Queue',
              onAction: controller.openPlayer,
            ),
            const SizedBox(height: 12),
            if (controller.upNextTracks.isEmpty)
              GlassPanel(
                padding: const EdgeInsets.all(18),
                child: Text(
                  'This is the only track in the active queue.',
                  style: textTheme.bodyLarge,
                ),
              )
            else
              for (final queuedTrack in controller.upNextTracks) ...[
                _QueueTile(track: queuedTrack),
                const SizedBox(height: 12),
              ],
          ],
        );
      },
    );
  }

  static IconData _repeatIcon(RepeatMode mode) {
    switch (mode) {
      case RepeatMode.off:
        return Icons.repeat_rounded;
      case RepeatMode.all:
        return Icons.repeat_on_rounded;
      case RepeatMode.one:
        return Icons.repeat_one_on_rounded;
    }
  }

  static Color _repeatColor(BuildContext context, RepeatMode mode) {
    final scheme = Theme.of(context).colorScheme;
    return mode == RepeatMode.off ? scheme.onSurfaceVariant : scheme.primary;
  }

  static String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _PlaybackDeck extends StatelessWidget {
  const _PlaybackDeck({
    required this.controller,
    required this.animation,
    required this.artworkAnimation,
    required this.availableWidth,
  });

  final MonolithController controller;
  final Animation<double> animation;
  final Animation<double> artworkAnimation;
  final double availableWidth;

  @override
  Widget build(BuildContext context) {
    final track = controller.currentTrack;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final artworkSize = math.max(120.0, math.min(availableWidth - 104, 248.0));
    final totalDuration = controller.currentTrackDuration;

    return GlassPanel(
      key: const Key('player-deck'),
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.headlineSmall?.copyWith(fontSize: 30),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh.withValues(alpha: 0.64),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.35),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  child: Text(
                    _sourceLabel(track.source),
                    style: textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Center(
            child: AnimatedBuilder(
              animation: artworkAnimation,
              builder: (context, child) {
                final pulse = controller.isPlaying
                    ? 1 +
                          (math.sin(artworkAnimation.value * math.pi * 2) *
                              0.028)
                    : 1.0;

                return Transform.scale(
                  scale: pulse,
                  child: Container(
                    width: artworkSize,
                    height: artworkSize,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          scheme.secondary.withValues(alpha: 0.38),
                          scheme.primary.withValues(alpha: 0.12),
                          scheme.surfaceContainerLow.withValues(alpha: 0.18),
                        ],
                      ),
                      border: Border.all(
                        color: scheme.primary.withValues(
                          alpha: controller.isPlaying ? 0.28 : 0.2,
                        ),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: scheme.primary.withValues(
                            alpha: controller.isPlaying ? 0.22 : 0.16,
                          ),
                          blurRadius: controller.isPlaying ? 34 : 28,
                          offset: const Offset(0, 18),
                        ),
                      ],
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: 0.32),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: ClipOval(
                          child: SizedBox.expand(
                            child: Transform.rotate(
                              angle: controller.isPlaying
                                  ? artworkAnimation.value * math.pi * 2
                                  : 0,
                              child: Hero(
                                tag: 'player-artwork-${track.id}',
                                child: TrackArtwork(
                                  track: track,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 18),
          _Visualizer(
            animation: animation,
            isPlaying: controller.isPlaying,
            colorA: scheme.primary,
            colorB: scheme.tertiary,
          ),
          const SizedBox(height: 14),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: controller.playbackProgress,
              onChanged: controller.setPlaybackProgress,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(PlayerPage._formatDuration(controller.currentPosition)),
              Text(PlayerPage._formatDuration(totalDuration)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _DeckToggleButton(
                key: const Key('player-shuffle'),
                onPressed: controller.toggleShuffle,
                icon: Icons.shuffle_rounded,
                tooltip: 'Shuffle',
                active: controller.shuffleEnabled,
              ),
              _DeckIconButton(
                key: const Key('player-prev'),
                onPressed: controller.previousTrack,
                icon: Icons.skip_previous_rounded,
                tooltip: 'Previous track',
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [scheme.primary, scheme.secondary],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.28),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: IconButton(
                  key: const Key('player-play-toggle'),
                  onPressed: track.canPlay ? controller.togglePlayback : null,
                  iconSize: 38,
                  color: Colors.white,
                  icon: Icon(
                    controller.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                  tooltip: controller.isPlaying ? 'Pause' : 'Play',
                ),
              ),
              _DeckIconButton(
                key: const Key('playback-next'),
                onPressed: track.canPlay
                    ? () => controller.nextTrack(openPlayer: true)
                    : null,
                icon: Icons.skip_next_rounded,
                tooltip: 'Next track',
              ),
              _DeckToggleButton(
                key: const Key('player-repeat'),
                onPressed: controller.cycleRepeatMode,
                icon: PlayerPage._repeatIcon(controller.repeatMode),
                tooltip: 'Repeat',
                active: controller.repeatMode != RepeatMode.off,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _sourceLabel(TrackSource source) {
    switch (source) {
      case TrackSource.mock:
        return 'Placeholder';
      case TrackSource.device:
        return 'Device library';
      case TrackSource.downloaded:
        return 'Downloaded';
      case TrackSource.imported:
        return 'Files import';
    }
  }
}

class _DeckIconButton extends StatelessWidget {
  const _DeckIconButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.tooltip,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.72),
        shape: BoxShape.circle,
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon),
        iconSize: 26,
        tooltip: tooltip,
      ),
    );
  }
}

class _DeckToggleButton extends StatelessWidget {
  const _DeckToggleButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.tooltip,
    required this.active,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final String tooltip;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: active
            ? scheme.primary.withValues(alpha: 0.12)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.58),
        shape: BoxShape.circle,
        border: Border.all(
          color: active
              ? scheme.primary.withValues(alpha: 0.36)
              : scheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: IconButton(
        key: key,
        onPressed: onPressed,
        icon: Icon(icon),
        tooltip: tooltip,
      ),
    );
  }
}

class _Visualizer extends StatelessWidget {
  const _Visualizer({
    required this.animation,
    required this.isPlaying,
    required this.colorA,
    required this.colorB,
  });

  final Animation<double> animation;
  final bool isPlaying;
  final Color colorA;
  final Color colorB;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(18, (index) {
              final wave = math.sin(
                (animation.value * math.pi * 2) + index / 2,
              );
              final height = isPlaying ? 10 + (wave.abs() * 30) : 8.0;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: 5,
                height: height,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [colorA, colorB],
                  ),
                ),
              );
            }),
          );
        },
      ),
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

    return Material(
      color: scheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: () => controller.selectTrack(track, openPlayer: true),
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              SizedBox(
                width: 58,
                height: 58,
                child: TrackArtwork(
                  track: track,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      '${track.artist} • ${track.genre}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
