import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app/state/app_controller.dart';
import '../../../app/state/app_scope.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../core/models/music_models.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/section_header.dart';
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
    final textTheme = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final deckWidth =
            math.max(0.0, math.min(availableWidth - 40, 420.0));

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
            const SizedBox(height: AppSpacing.xxl),
            SectionHeader(
              title: 'Next songs',
              actionLabel: 'Queue',
              onAction: controller.openPlayer,
            ),
            const SizedBox(height: AppSpacing.md),
            if (controller.upNextTracks.isEmpty)
              GlassPanel(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  'This is the only track in the active queue.',
                  style: textTheme.bodyLarge,
                ),
              )
            else
              for (final queuedTrack in controller.upNextTracks) ...[
                _QueueTile(track: queuedTrack),
                const SizedBox(height: AppSpacing.md),
              ],
          ],
        );
      },
    );
  }

  static PhosphorIconData _repeatIcon(RepeatMode mode) {
    switch (mode) {
      case RepeatMode.off:
        return AppIcons.repeat;
      case RepeatMode.all:
        return AppIcons.repeatFill;
      case RepeatMode.one:
        return AppIcons.repeatOne;
    }
  }

  static String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds =
        duration.inSeconds.remainder(60).toString().padLeft(2, '0');
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
    final artworkSize =
        math.max(120.0, math.min(availableWidth - 104, 248.0));
    final totalDuration = controller.currentTrackDuration;

    return GlassPanel(
      key: const Key('player-deck'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
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
                      style:
                          textTheme.headlineSmall?.copyWith(fontSize: 30),
                    ),
                    const SizedBox(height: AppSpacing.xs),
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
              const SizedBox(width: AppSpacing.md),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh
                      .withValues(alpha: 0.64),
                  borderRadius: AppRadii.all(AppRadii.pill),
                  border: Border.all(
                    color:
                        scheme.outlineVariant.withValues(alpha: 0.35),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs + 3,
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
          const SizedBox(height: AppSpacing.xl),
          Center(
            child: AnimatedBuilder(
              animation: artworkAnimation,
              builder: (context, child) {
                final pulse = controller.isPlaying
                    ? 1 +
                          (math.sin(
                                artworkAnimation.value * math.pi * 2,
                              ) *
                              0.028)
                    : 1.0;

                return Transform.scale(
                  scale: pulse,
                  child: Container(
                    width: artworkSize,
                    height: artworkSize,
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          scheme.secondary.withValues(alpha: 0.38),
                          scheme.primary.withValues(alpha: 0.12),
                          scheme.surfaceContainerLow
                              .withValues(alpha: 0.18),
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
                            alpha:
                                controller.isPlaying ? 0.22 : 0.16,
                          ),
                          blurRadius:
                              controller.isPlaying ? 34 : 28,
                          offset: const Offset(0, AppSpacing.lg),
                        ),
                      ],
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: scheme.outlineVariant
                              .withValues(alpha: 0.32),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: ClipOval(
                          child: SizedBox.expand(
                            child: Transform.rotate(
                              angle: controller.isPlaying
                                  ? artworkAnimation.value *
                                        math.pi *
                                        2
                                  : 0,
                              child: Hero(
                                tag: 'player-artwork-${track.id}',
                                child: TrackArtwork(
                                  track: track,
                                  borderRadius:
                                      AppRadii.all(AppRadii.pill),
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
          const SizedBox(height: AppSpacing.lg),
          _Visualizer(
            animation: animation,
            isPlaying: controller.isPlaying,
            colorA: scheme.primary,
            colorB: scheme.tertiary,
          ),
          const SizedBox(height: AppSpacing.md),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 5,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape:
                  const RoundSliderOverlayShape(overlayRadius: 14),
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
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _DeckToggleButton(
                key: const Key('player-shuffle'),
                onPressed: controller.toggleShuffle,
                icon: controller.shuffleEnabled
                    ? AppIcons.shuffleFill
                    : AppIcons.shuffle,
                tooltip: 'Shuffle',
                active: controller.shuffleEnabled,
              ),
              _DeckIconButton(
                key: const Key('player-prev'),
                onPressed: controller.previousTrack,
                icon: AppIcons.skipBack,
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
                      color:
                          scheme.primary.withValues(alpha: 0.28),
                      blurRadius: 18,
                      offset: const Offset(0, AppSpacing.sm + AppSpacing.xs),
                    ),
                  ],
                ),
                child: IconButton(
                  key: const Key('player-play-toggle'),
                  onPressed:
                      track.canPlay ? controller.togglePlayback : null,
                  iconSize: 38,
                  color: Colors.white,
                  icon: PhosphorIcon(
                    controller.isPlaying ? AppIcons.pause : AppIcons.play,
                  ),
                  tooltip: controller.isPlaying ? 'Pause' : 'Play',
                ),
              ),
              _DeckIconButton(
                key: const Key('playback-next'),
                onPressed: track.canPlay
                    ? () => controller.nextTrack(openPlayer: true)
                    : null,
                icon: AppIcons.skipForward,
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
  final PhosphorIconData icon;
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
        icon: PhosphorIcon(icon),
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
  final PhosphorIconData icon;
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
        icon: PhosphorIcon(icon),
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
                duration: AppMotion.durFast,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: 5,
                height: height,
                decoration: BoxDecoration(
                  borderRadius: AppRadii.all(AppRadii.pill),
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
      borderRadius: AppRadii.all(AppRadii.md),
      child: InkWell(
        onTap: () => controller.selectTrack(track, openPlayer: true),
        borderRadius: AppRadii.all(AppRadii.md),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              SizedBox(
                width: 58,
                height: 58,
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
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      '${track.artist} • ${track.genre}',
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              PhosphorIcon(AppIcons.caretRight),
            ],
          ),
        ),
      ),
    );
  }
}
