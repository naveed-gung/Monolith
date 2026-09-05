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
    // Only spin the reactive visualizer when it can actually be seen and the
    // user wants it: the player sheet is open, audio is playing, and immersive
    // canvas is on. Leaving it running behind a closed sheet (or with the
    // toggle off) just pegged the CPU/GPU and cooked the phone for no visible
    // benefit.
    final shouldAnimate =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
        !controller.reduceVisualEffects &&
        controller.isPlaying &&
        controller.isPlayerOpen &&
        controller.immersiveCanvas;
    if (shouldAnimate) {
      if (!_visualizerController.isAnimating) _visualizerController.repeat();
    } else if (_visualizerController.isAnimating) {
      _visualizerController.stop();
    }
    // The slow artwork rotation is unused for visuals; keep it parked.
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.watch(context);

    // Keep the swipeable PageView aligned with tab changes that originate from
    // the bottom nav (a tap) instead of a swipe. We skip this while the view is
    // actively scrolling so a programmatic animation never fights the finger.
    // Only schedule a page sync when the tab actually changed. build() runs on
    // every controller notify (≈1–4×/sec during playback), and scheduling a
    // post-frame callback every time kept the engine doing continuous frame
    // work — denying the SoC idle gaps and cooking the phone. Guarding on the
    // tab index makes this fire only on real tab changes.
    final tabIndex = AppTab.values.indexOf(controller.currentTab);
    if (tabIndex != _lastSyncedTabIndex) {
      _lastSyncedTabIndex = tabIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final pc = _pageController;
        if (!mounted || pc == null || !pc.hasClients) return;
        if (pc.page?.round() == tabIndex) return;
        // Skip while a finger drag or an in-flight animation owns the view, so
        // a programmatic jump never fights the user's swipe.
        if (pc.position.isScrollingNotifier.value) return;
        pc.animateToPage(
          tabIndex,
          duration: AppMotion.durMedium,
          curve: AppMotion.emphasized,
        );
      });
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wideLayout = constraints.maxWidth > 880;
        final currentPage = _buildPage(controller);

        final miniTrack = controller.currentTrack;

        return Scaffold(
          extendBody: true,
          // Keep the body (and its bottom-anchored mini player + nav bar) put
          // when the keyboard opens. Without this the body shrinks above the
          // keyboard and the mini player jumps up with it. All text inputs sit
          // in the upper portion of each screen, so they stay visible.
          resizeToAvoidBottomInset: false,
          body: Stack(
            children: [
              const Positioned.fill(child: Atmosphere()),
              currentPage,
              // Mini player — above page content, below player overlay.
              // Hidden when nothing is loaded.
              if (!controller.isPlayerOpen && miniTrack != null)
                Positioned(
                  left: AppSpacing.lg,
                  right: AppSpacing.lg,
                  bottom:
                      _kNavBarHeight +
                      MediaQuery.of(context).viewPadding.bottom +
                      _kMiniPlayerGap,
                  child: _MiniPlayer(controller: controller, track: miniTrack),
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
              : _BottomNav(controller: controller),
        );
      },
    );
  }

  Widget _buildPage(MonolithController controller) {
    // Horizontally swipeable tabs. Child order MUST match AppTab.values so a
    // settled page maps back to the right tab. A hard left→right swipe moves to
    // the previous tab (e.g. Downloads → Library); right→left to the next.
    return PageView(
      controller: _pageController,
      physics: const BouncingScrollPhysics(),
      onPageChanged: (index) => controller.selectTab(AppTab.values[index]),
      children: [
        SafeArea(
          bottom: false,
          child: LibraryPage(
            key: const ValueKey('library'),
            onOpenSettings: _openSettings,
          ),
        ),
        const SafeArea(
          bottom: false,
          child: DownloadsPage(key: ValueKey('downloads'), embedded: true),
        ),
        const SafeArea(
          bottom: false,
          child: SearchPage(key: ValueKey('search')),
        ),
      ],
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
  const _BottomNav({required this.controller});
  final MonolithController controller;

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
          height: _kNavBarHeight,
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

    // RepaintBoundary caches the blurred nav so a repaint above it (page swipe,
    // mini-player tick) can't force the backdrop to re-rasterize every frame —
    // the always-on-screen blur was a primary heat source on A11.
    return RepaintBoundary(
      child: ClipRect(key: const Key('bottom-nav'), child: bar),
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
  const _MiniPlayer({required this.controller, required this.track});
  final MonolithController controller;
  final Track track;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return GlassPanel(
      key: const Key('mini-player'),
      borderRadius: AppRadii.all(AppRadii.xl),
      padding: EdgeInsets.zero,
      reduceEffects: controller.reduceVisualEffects,
      child: Material(
        color: Colors.transparent,
        child: ClipRRect(
          borderRadius: AppRadii.all(AppRadii.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Main row
              InkWell(
                onTap: () {
                  controller.hapticLight();
                  controller.openPlayer();
                },
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
        color: scheme.surface,
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
