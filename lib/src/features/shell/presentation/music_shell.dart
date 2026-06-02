import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app/state/app_controller.dart';
import '../../../app/state/app_scope.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../core/models/music_models.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/atmosphere.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/track_artwork.dart';
import '../../downloads/presentation/downloads_page.dart';
import '../../library/presentation/library_page.dart';
import '../../player/presentation/player_page.dart';
import '../../search/presentation/search_page.dart';
import '../../settings/presentation/settings_page.dart';

const _kNavBarHeight = 84.0;
const _kMiniPlayerGap = AppSpacing.sm;

class MusicShell extends StatefulWidget {
  const MusicShell({super.key});

  @override
  State<MusicShell> createState() => _MusicShellState();
}

class _MusicShellState extends State<MusicShell>
    with TickerProviderStateMixin {
  late final AnimationController _visualizerController;
  late final AnimationController _artworkController;
  MonolithController? _controller;

  @override
  void initState() {
    super.initState();
    _visualizerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    );
    _artworkController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = AppScope.watch(context);
    if (controller != _controller) {
      _controller?.removeListener(_handleControllerChanged);
      _controller = controller;
      _controller?.addListener(_handleControllerChanged);
      _handleControllerChanged();
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_handleControllerChanged);
    _visualizerController.dispose();
    _artworkController.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    final controller = _controller;
    if (controller == null || !mounted) return;
    if (controller.isPlaying) {
      if (!_visualizerController.isAnimating) _visualizerController.repeat();
      if (!_artworkController.isAnimating) _artworkController.repeat();
    } else {
      _visualizerController.stop();
      _artworkController.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.watch(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wideLayout = constraints.maxWidth > 880;
        final currentPage = _buildPage(controller);

        return Scaffold(
          extendBody: true,
          body: Stack(
            children: [
              const Positioned.fill(child: Atmosphere()),
              currentPage,
              // Mini player — above page content, below player overlay
              if (!controller.isPlayerOpen)
                Positioned(
                  left: AppSpacing.lg,
                  right: AppSpacing.lg,
                  bottom: _kNavBarHeight +
                      MediaQuery.of(context).viewPadding.bottom +
                      _kMiniPlayerGap,
                  child: _MiniPlayer(controller: controller),
                ),
              // Player overlay
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !controller.isPlayerOpen,
                  child: AnimatedSwitcher(
                    duration: AppMotion.durSlow,
                    switchInCurve: AppMotion.emphasized,
                    switchOutCurve: AppMotion.exit,
                    transitionBuilder: (child, anim) {
                      return FadeTransition(
                        opacity: CurvedAnimation(
                          parent: anim,
                          curve: AppMotion.standard,
                        ),
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 1),
                            end: Offset.zero,
                          ).animate(
                            CurvedAnimation(
                              parent: anim,
                              curve: AppMotion.emphasized,
                            ),
                          ),
                          child: child,
                        ),
                      );
                    },
                    child: controller.isPlayerOpen
                        ? _PlayerOverlay(
                            key: const ValueKey('player-overlay'),
                            controller: controller,
                            animation: _visualizerController,
                            artworkAnimation: _artworkController,
                          )
                        : const SizedBox.shrink(
                            key: ValueKey('player-overlay-hidden'),
                          ),
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: wideLayout
              ? null
              : _BottomNav(controller: controller),
        );
      },
    );
  }

  Widget _buildPage(MonolithController controller) {
    final inner = switch (controller.currentTab) {
      AppTab.library => LibraryPage(
          key: const ValueKey('library'),
          onOpenSettings: _openSettings,
        ),
      AppTab.downloads => const DownloadsPage(
          key: ValueKey('downloads'),
          embedded: true,
        ),
      AppTab.search => const SearchPage(key: ValueKey('search')),
    };

    return AnimatedSwitcher(
      duration: AppMotion.durFast,
      switchInCurve: AppMotion.standard,
      switchOutCurve: AppMotion.exit,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: child,
      ),
      child: SafeArea(
        key: ValueKey(controller.currentTab),
        bottom: false,
        child: inner,
      ),
    );
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => const SettingsPage(),
        transitionDuration: AppMotion.durMedium,
        reverseTransitionDuration: AppMotion.durFast,
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: AppMotion.standard),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.04),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: animation, curve: AppMotion.emphasized),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ── Bottom navigation bar ──────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.controller});
  final MonolithController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final selected = AppTab.values.indexOf(controller.currentTab);

    return ClipRect(
      key: const Key('bottom-nav'),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: (brightness == Brightness.dark ? Colors.black : Colors.white)
                .withValues(alpha: 0.82),
            border: Border(
              top: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.4),
                width: 0.5,
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: _kNavBarHeight,
              child: Row(
                children: [
                  for (final tab in AppTab.values)
                    Expanded(
                      child: _NavItem(
                        tab: tab,
                        isSelected: AppTab.values.indexOf(tab) == selected,
                        onTap: () => controller.selectTab(tab),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.tab,
    required this.isSelected,
    required this.onTap,
  });

  final AppTab tab;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = switch (tab) {
      AppTab.library => 'Library',
      AppTab.downloads => 'Downloads',
      AppTab.search => 'Search',
    };
    final icon = switch (tab) {
      AppTab.library => AppIcons.navLibrary(isSelected),
      AppTab.downloads => AppIcons.navDownloads(isSelected),
      AppTab.search => AppIcons.navSearch(isSelected),
    };

    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      child: InkResponse(
        onTap: onTap,
        radius: 32,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: ExcludeSemantics(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedScale(
                  scale: isSelected ? 1.12 : 1.0,
                  duration: AppMotion.durFast,
                  curve: AppMotion.standard,
                  child: PhosphorIcon(
                    key: Key('nav-${tab.name}-icon'),
                    icon,
                    size: 26,
                    color: isSelected
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 3),
                AnimatedDefaultTextStyle(
                  duration: AppMotion.durFast,
                  style: Theme.of(context).textTheme.labelSmall!.copyWith(
                        color: isSelected
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                        fontWeight: isSelected ? AppType.label : AppType.body,
                      ),
                  child: Text(label),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Mini player ────────────────────────────────────────────────────────────

class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer({required this.controller});
  final MonolithController controller;

  @override
  Widget build(BuildContext context) {
    final track = controller.currentTrack;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return GlassPanel(
      key: const Key('mini-player'),
      borderRadius: AppRadii.all(AppRadii.xl),
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: ClipRRect(
          borderRadius: AppRadii.all(AppRadii.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Main row
              InkWell(
                onTap: controller.openPlayer,
                borderRadius: AppRadii.all(AppRadii.xl),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.sm,
                    AppSpacing.sm,
                    AppSpacing.sm,
                    AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      // Artwork
                      SizedBox(
                        width: 52,
                        height: 52,
                        child: Hero(
                          tag: 'player-artwork-${track.id}',
                          child: TrackArtwork(
                            track: track,
                            borderRadius: AppRadii.all(AppRadii.md),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      // Title + artist
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.titleSmall?.copyWith(
                                fontWeight: AppType.label,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Controls
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _MiniButton(
                            icon: AppIcons.skipBack,
                            onPressed: controller.previousTrack,
                            size: 22,
                            tooltip: 'Previous',
                          ),
                          _MiniButton(
                            icon: controller.isPlaying
                                ? AppIcons.pauseCircle
                                : AppIcons.playCircle,
                            onPressed: track.canPlay
                                ? controller.togglePlayback
                                : null,
                            size: 32,
                            color: scheme.primary,
                            tooltip: controller.isPlaying ? 'Pause' : 'Play',
                          ),
                          _MiniButton(
                            icon: AppIcons.skipForward,
                            onPressed: () =>
                                controller.nextTrack(openPlayer: false),
                            size: 22,
                            tooltip: 'Next',
                          ),
                        ],
                      ),
                      const SizedBox(width: AppSpacing.xs),
                    ],
                  ),
                ),
              ),
              // Thin progress bar
              SizedBox(
                height: 3,
                child: ClipRRect(
                  borderRadius: AppRadii.all(AppRadii.pill),
                  child: LinearProgressIndicator(
                    value: controller.playbackProgress,
                    backgroundColor: scheme.outlineVariant.withValues(alpha: 0.3),
                    valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
                    minHeight: 3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({
    required this.icon,
    required this.onPressed,
    required this.size,
    this.color,
    this.tooltip,
  });

  final PhosphorIconData icon;
  final VoidCallback? onPressed;
  final double size;
  final Color? color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: PhosphorIcon(
        icon,
        size: size,
        color: color ?? scheme.onSurface,
      ),
      padding: const EdgeInsets.all(AppSpacing.xs),
      constraints: BoxConstraints(minWidth: size + 8, minHeight: size + 8),
    );
  }
}

// ── Player overlay (full sheet) ────────────────────────────────────────────

class _PlayerOverlay extends StatefulWidget {
  const _PlayerOverlay({
    super.key,
    required this.controller,
    required this.animation,
    required this.artworkAnimation,
  });

  final MonolithController controller;
  final Animation<double> animation;
  final Animation<double> artworkAnimation;

  @override
  State<_PlayerOverlay> createState() => _PlayerOverlayState();
}

class _PlayerOverlayState extends State<_PlayerOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _settleController;
  Animation<double>? _settleAnimation;
  double _dragOffset = 0;

  @override
  void initState() {
    super.initState();
    _settleController = AnimationController(
      vsync: this,
      duration: AppMotion.durMedium,
    )..addListener(() {
        final animation = _settleAnimation;
        if (animation == null || !mounted) return;
        setState(() => _dragOffset = animation.value);
      });
  }

  @override
  void dispose() {
    _settleController.dispose();
    super.dispose();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    _settleController.stop();
    final dy = details.primaryDelta ?? details.delta.dy;
    if (dy == 0) return;
    setState(() {
      _dragOffset = (_dragOffset + dy).clamp(0.0, 420.0);
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final shouldClose = velocity > 650 || _dragOffset > 120;

    if (shouldClose) {
      // Slide the sheet off screen along the drag direction, then close.
      final screenH = MediaQuery.sizeOf(context).height;
      _settleController.duration = const Duration(milliseconds: 220);
      _settleAnimation = Tween<double>(
        begin: _dragOffset,
        end: screenH,
      ).animate(
        CurvedAnimation(parent: _settleController, curve: Curves.easeIn),
      );
      _settleController
        ..reset()
        ..forward().whenComplete(() {
          _settleController.duration = AppMotion.durMedium;
          if (mounted) widget.controller.closePlayer();
        });
      return;
    }

    // Spring back to resting position.
    _settleController.duration = AppMotion.durMedium;
    _settleAnimation = Tween<double>(
      begin: _dragOffset,
      end: 0,
    ).animate(
      CurvedAnimation(parent: _settleController, curve: AppMotion.emphasized),
    );
    _settleController
      ..reset()
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    return Transform.translate(
      offset: Offset(0, _dragOffset),
      child: Container(
        key: const Key('player-overlay-sheet'),
        color: (brightness == Brightness.dark
                ? AppSurfaces.dark.canvas
                : AppSurfaces.light.canvas)
            .withValues(alpha: 0.97),
        child: SafeArea(
          child: Column(
            children: [
              // Drag handle — follows your finger, then settles or closes.
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragUpdate: _handleDragUpdate,
                onVerticalDragEnd: _handleDragEnd,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenInset,
                    AppSpacing.lg,
                    AppSpacing.screenInset,
                    AppSpacing.md,
                  ),
                  child: Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: scheme.outlineVariant,
                        borderRadius: AppRadii.all(AppRadii.pill),
                      ),
                    ),
                  ),
                ),
              ),
              // Player content
              Expanded(
                child: PlayerPage(
                  key: const Key('player-deck'),
                  animation: widget.animation,
                  artworkAnimation: widget.artworkAnimation,
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenInset,
                    AppSpacing.sm,
                    AppSpacing.screenInset,
                    AppSpacing.xl,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
