import 'dart:async';

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
import '../../songs/presentation/songs_page.dart';

const _kNavBarHeight = 84.0;
const _kMiniPlayerGap = AppSpacing.sm;

class MusicShell extends StatefulWidget {
  const MusicShell({super.key});

  @override
  State<MusicShell> createState() => _MusicShellState();
}

class _MusicShellState extends State<MusicShell>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _visualizerController;
  late final AnimationController _artworkController;
  // Created once the controller is known so it can open on the correct tab
  // (default is Downloads) with no first-frame flash.
  PageController? _pageController;
  int? _lastSyncedTabIndex;
  MonolithController? _controller;
  bool _isMiniPlayerDismissed = false;
  String? _lastTrackId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    _pageController ??= PageController(
      initialPage: AppTab.values.indexOf(controller.currentTab),
    );
    if (controller != _controller) {
      _controller?.removeListener(_handleControllerChanged);
      _controller = controller;
      _controller?.addListener(_handleControllerChanged);
      _handleControllerChanged();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.removeListener(_handleControllerChanged);
    _visualizerController.dispose();
    _artworkController.dispose();
    _pageController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _handleControllerChanged();

  void _handleControllerChanged() {
    final controller = _controller;
    if (controller == null || !mounted) return;
    // Artwork tint is static. Keep compatibility animations idle, including
    // when reduced effects is disabled, instead of spending frames on a glow.
    _visualizerController.stop();
    _artworkController.stop();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.watch(context);

    final tabIndex = AppTab.values.indexOf(controller.currentTab);
    if (tabIndex != _lastSyncedTabIndex) {
      _lastSyncedTabIndex = tabIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final pc = _pageController;
        if (!mounted || pc == null || !pc.hasClients) return;
        if (pc.page?.round() == tabIndex) return;
        if (pc.position.isScrollingNotifier.value) return;
        pc.animateToPage(
          tabIndex,
          duration: AppMotion.durMedium,
          curve: AppMotion.emphasized,
        );
      });
    }

    final miniTrack = controller.currentTrack;
    if (miniTrack?.id != _lastTrackId) {
      _lastTrackId = miniTrack?.id;
      _isMiniPlayerDismissed = false;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wideLayout = constraints.maxWidth > 880;
        final currentPage = _buildPage(controller);

        return Scaffold(
          extendBody: false,
          resizeToAvoidBottomInset: false,
          body: Stack(
            children: [
              const Positioned.fill(child: Atmosphere()),
              currentPage,
              // Mini player — above page content, below player overlay.
              // Gesture down hides it; gesture up opens full player.
              if (!controller.isPlayerOpen &&
                  miniTrack != null &&
                  !_isMiniPlayerDismissed)
                Positioned(
                  left: AppSpacing.lg,
                  right: AppSpacing.lg,
                  bottom: _kMiniPlayerGap,
                  child: GestureDetector(
                    onVerticalDragEnd: (details) {
                      final velocity = details.primaryVelocity ?? 0;
                      if (velocity > 200) {
                        // Swiped down -> dismiss mini player
                        controller.hapticLight();
                        setState(() => _isMiniPlayerDismissed = true);
                      } else if (velocity < -200) {
                        // Swiped up -> open full player
                        controller.hapticMedium();
                        controller.openPlayer();
                      }
                    },
                    child: _MiniPlayer(
                      controller: controller,
                      track: miniTrack,
                    ),
                  ),
                ),
              // If mini player was dismissed, show subtle floating pill to reshow
              if (!controller.isPlayerOpen &&
                  miniTrack != null &&
                  _isMiniPlayerDismissed)
                Positioned(
                  bottom: 4,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: () {
                        controller.hapticLight();
                        setState(() => _isMiniPlayerDismissed = false);
                      },
                      onVerticalDragEnd: (details) {
                        if ((details.primaryVelocity ?? 0) < -150) {
                          controller.hapticLight();
                          setState(() => _isMiniPlayerDismissed = false);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                          border: Border.all(
                            color: Theme.of(
                              context,
                            ).colorScheme.outlineVariant.withValues(alpha: 0.5),
                            width: 0.5,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            PhosphorIcon(
                              PhosphorIcons.caretUp(),
                              size: 14,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              miniTrack.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
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
                          position:
                              Tween<Offset>(
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
              : _BottomNav(
                  controller: controller,
                  onSwipeUp: () {
                    if (_isMiniPlayerDismissed) {
                      controller.hapticLight();
                      setState(() => _isMiniPlayerDismissed = false);
                    }
                  },
                ),
        );
      },
    );
  }

  Widget _buildPage(MonolithController controller) {
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (details) {
        if (isKeyboardOpen ||
            FocusManager.instance.primaryFocus?.hasFocus == true) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity.abs() > 80) {
            FocusScope.of(context).unfocus();
          }
        }
      },
      child: PageView(
        controller: _pageController,
        physics: isKeyboardOpen
            ? const NeverScrollableScrollPhysics()
            : const BouncingScrollPhysics(),
        onPageChanged: (index) => controller.selectTab(AppTab.values[index]),
        children: [
          SafeArea(
            bottom: false,
            child: LibraryPage(
              key: const ValueKey('library'),
              onOpenSettings: _openSettings,
              onSwipeToNextTab: () => _pageController?.animateToPage(
                1,
                duration: AppMotion.durMedium,
                curve: AppMotion.emphasized,
              ),
            ),
          ),
          const SafeArea(
            bottom: false,
            child: DownloadsPage(key: ValueKey('downloads'), embedded: true),
          ),
          const SafeArea(bottom: false, child: SongsPage(key: ValueKey('songs'))),
          const SafeArea(
            bottom: false,
            child: SearchPage(key: ValueKey('search')),
          ),
        ],
      ),
    );
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => const SettingsPage(),
        transitionDuration: AppMotion.durMedium,
        reverseTransitionDuration: AppMotion.durMedium,
        // Horizontal page slide: enters from the right, and on pop the whole
        // screen swipes back off to the right (iOS-style). "Open player" relies
        // on this reverse to glide Settings away as the player rises.
        transitionsBuilder: (_, animation, _, child) => SlideTransition(
          position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
              .animate(
                CurvedAnimation(
                  parent: animation,
                  curve: AppMotion.emphasized,
                  reverseCurve: AppMotion.exit,
                ),
              ),
          child: child,
        ),
      ),
    );
  }
}

// ── Bottom navigation bar ──────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.controller, this.onSwipeUp});
  final MonolithController controller;
  final VoidCallback? onSwipeUp;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final selected = AppTab.values.indexOf(controller.currentTab);
    final reduceEffects = controller.reduceVisualEffects;

    final bar = DecoratedBox(
      decoration: BoxDecoration(
        color: (brightness == Brightness.dark ? Colors.black : Colors.white)
            // Flat fill needs more opacity to hide the content scrolling under
            // it once the blur is gone.
            .withValues(alpha: reduceEffects ? 0.95 : 0.82),
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
          height:
              _kNavBarHeight +
              (MediaQuery.textScalerOf(context).scale(12) - 12).clamp(0, 24),
          child: Row(
            children: [
              for (final tab in AppTab.values)
                Expanded(
                  child: _NavItem(
                    tab: tab,
                    isSelected: AppTab.values.indexOf(tab) == selected,
                    onTap: () {
                      controller.hapticSelection();
                      controller.selectTab(tab);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    return RepaintBoundary(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0) < -150) {
            onSwipeUp?.call();
          }
        },
        child: ClipRect(key: const Key('bottom-nav'), child: bar),
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
      AppTab.songs => 'Songs',
      AppTab.search => 'Search',
    };
    final icon = switch (tab) {
      AppTab.library => AppIcons.navLibrary(isSelected),
      AppTab.downloads => AppIcons.navDownloads(isSelected),
      AppTab.songs => AppIcons.navSongs(isSelected),
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
                  scale: 1.0,
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
  const _MiniPlayer({required this.controller, required this.track});
  final MonolithController controller;
  final Track track;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return GlassPanel(
      key: const Key('mini-player'),
      borderRadius: AppRadii.all(AppRadii.md),
      padding: EdgeInsets.zero,
      reduceEffects: controller.reduceVisualEffects,
      child: Material(
        color: Colors.transparent,
        child: ClipRRect(
          borderRadius: AppRadii.all(AppRadii.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Main row
              InkWell(
                onTap: () {
                  controller.hapticLight();
                  controller.openPlayer();
                },
                borderRadius: AppRadii.all(AppRadii.md),
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
                        width: 44,
                        height: 44,
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
                            onPressed: () {
                              controller.hapticLight();
                              controller.previousTrack();
                            },
                            size: 22,
                            tooltip: 'Previous',
                          ),
                          _MiniButton(
                            icon: controller.isPlaying
                                ? AppIcons.pauseCircle
                                : AppIcons.playCircle,
                            onPressed: track.canPlay
                                ? () {
                                    controller.hapticMedium();
                                    controller.togglePlayback();
                                  }
                                : null,
                            size: 32,
                            color: scheme.primary,
                            tooltip: controller.isPlaying ? 'Pause' : 'Play',
                          ),
                          _MiniButton(
                            icon: AppIcons.skipForward,
                            onPressed: () {
                              controller.hapticLight();
                              controller.nextTrack(openPlayer: false);
                            },
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
              // Thin progress bar — repaints in isolation off the progress
              // notifier so a position tick never rebuilds the whole shell.
              SizedBox(
                height: 3,
                child: ClipRRect(
                  borderRadius: AppRadii.all(AppRadii.pill),
                  child: RepaintBoundary(
                    child: ValueListenableBuilder<double>(
                      valueListenable: controller.progress,
                      builder: (_, value, _) => LinearProgressIndicator(
                        value: value,
                        backgroundColor: scheme.outlineVariant.withValues(
                          alpha: 0.3,
                        ),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          scheme.primary,
                        ),
                        minHeight: 3,
                      ),
                    ),
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
      icon: PhosphorIcon(icon, size: size, color: color ?? scheme.onSurface),
      padding: const EdgeInsets.all(AppSpacing.xs),
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
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
    _settleController =
        AnimationController(vsync: this, duration: AppMotion.durMedium)
          ..addListener(() {
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
      _settleAnimation = Tween<double>(begin: _dragOffset, end: screenH)
          .animate(
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
    _settleAnimation = Tween<double>(begin: _dragOffset, end: 0).animate(
      CurvedAnimation(parent: _settleController, curve: AppMotion.emphasized),
    );
    _settleController
      ..reset()
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Transform.translate(
      offset: Offset(0, _dragOffset),
      child: Container(
        key: const Key('player-overlay-sheet'),
        color:
            widget.controller.immersiveCanvas &&
                widget.controller.currentTrack != null
            ? Color.alphaBlend(
                widget.controller.currentTrack!.colors.first.withValues(
                  alpha: 0.035,
                ),
                scheme.surface,
              )
            : scheme.surface,
        child: SafeArea(
          child: Column(
            children: [
              // Drag handle — follows your finger, then settles or closes.
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: widget.controller.closePlayer,
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
