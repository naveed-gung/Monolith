import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app/state/app_controller.dart';
import '../../../app/state/app_scope.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../core/models/music_models.dart';
import '../../../core/widgets/app_header.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/atmosphere.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/track_artwork.dart';
import '../../downloads/presentation/downloads_page.dart';
import '../../library/presentation/library_page.dart';
import '../../player/presentation/player_page.dart';
import '../../search/presentation/search_page.dart';
import '../../settings/presentation/settings_page.dart';

const _kBottomNavigationFootprint = 104.0;
const _kMiniPlayerBottomGap = AppSpacing.md;

class MusicShell extends StatefulWidget {
  const MusicShell({super.key});

  @override
  State<MusicShell> createState() => _MusicShellState();
}

class _MusicShellState extends State<MusicShell> with TickerProviderStateMixin {
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
      duration: const Duration(seconds: 18),
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
        final currentPage = _buildCurrentPage(controller);

        return Scaffold(
          extendBody: !wideLayout,
          body: Stack(
            children: [
              const Positioned.fill(child: Atmosphere()),
              SafeArea(
                bottom: false,
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: wideLayout ? 1280 : 480,
                    ),
                    child: wideLayout
                        ? _WideShell(
                            currentPage: currentPage,
                            controller: controller,
                            header: _buildHeader(controller),
                            artworkAnimation: _artworkController,
                          )
                        : _NarrowShell(
                            currentPage: currentPage,
                            controller: controller,
                            header: _buildHeader(controller),
                            artworkAnimation: _artworkController,
                          ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !controller.isPlayerOpen,
                  child: AnimatedSwitcher(
                    duration: AppMotion.durMedium,
                    switchInCurve: AppMotion.standard,
                    switchOutCurve: AppMotion.exit,
                    transitionBuilder: (child, animation) {
                      final curve = CurvedAnimation(
                        parent: animation,
                        curve: AppMotion.standard,
                        reverseCurve: AppMotion.exit,
                      );
                      return FadeTransition(
                        opacity: curve,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.08),
                            end: Offset.zero,
                          ).animate(curve),
                          child: ScaleTransition(
                            scale: Tween<double>(
                              begin: 0.985,
                              end: 1,
                            ).animate(curve),
                            child: child,
                          ),
                        ),
                      );
                    },
                    child: controller.isPlayerOpen
                        ? _PlayerOverlay(
                            key: const ValueKey('player-overlay'),
                            controller: controller,
                            animation: _visualizerController,
                            artworkAnimation: _artworkController,
                            wideLayout: wideLayout,
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
              : _BottomNavigation(controller: controller),
        );
      },
    );
  }

  Widget _buildCurrentPage(MonolithController controller) {
    switch (controller.currentTab) {
      case AppTab.library:
        return const LibraryPage();
      case AppTab.downloads:
        return const DownloadsPage(embedded: true);
      case AppTab.search:
        return const SearchPage();
    }
  }

  Widget _buildHeader(MonolithController controller) {
    return AppHeader(
      onMenuPressed: _openDownloads,
      onProfilePressed: _openSettings,
      statusLabel: 'Settings',
    );
  }

  Future<void> _openDownloads() async {
    _controller?.selectTab(AppTab.downloads);
  }

  Future<void> _openSettings() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SettingsPage()));
  }
}

class _NarrowShell extends StatelessWidget {
  const _NarrowShell({
    required this.currentPage,
    required this.controller,
    required this.header,
    required this.artworkAnimation,
  });

  final Widget currentPage;
  final MonolithController controller;
  final Widget header;
  final Animation<double> artworkAnimation;

  @override
  Widget build(BuildContext context) {
    final showMiniPlayer = !controller.isPlayerOpen;

    return Stack(
      children: [
        Column(
          children: [
            header,
            Expanded(
              child: KeyedSubtree(
                key: ValueKey(controller.currentTab),
                child: currentPage,
              ),
            ),
          ],
        ),
        if (showMiniPlayer)
          Positioned(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            bottom: _kBottomNavigationFootprint + _kMiniPlayerBottomGap,
            child: AnimatedSlide(
              duration: AppMotion.durMedium,
              curve: AppMotion.standard,
              offset: showMiniPlayer ? Offset.zero : const Offset(0, 0.18),
              child: AnimatedOpacity(
                duration: AppMotion.durFast,
                opacity: showMiniPlayer ? 1 : 0,
                child: _MiniPlayer(controller: controller),
              ),
            ),
          ),
      ],
    );
  }
}

class _WideShell extends StatelessWidget {
  const _WideShell({
    required this.currentPage,
    required this.controller,
    required this.header,
    required this.artworkAnimation,
  });

  final Widget currentPage;
  final MonolithController controller;
  final Widget header;
  final Animation<double> artworkAnimation;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RailNavigation(controller: controller),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            flex: 2,
            child: GlassPanel(
              child: Column(
                children: [
                  header,
                  Expanded(
                    child: KeyedSubtree(
                      key: ValueKey(controller.currentTab),
                      child: currentPage,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          SizedBox(
            width: 320,
            child: Column(
              children: [
                AnimatedOpacity(
                  duration: AppMotion.durFast,
                  opacity: controller.isPlayerOpen ? 0.25 : 1,
                  child: IgnorePointer(
                    ignoring: controller.isPlayerOpen,
                    child: _MiniPlayer(controller: controller),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                GlassPanel(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionHeader(title: 'Operations'),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'Theme: ${controller.themePreference.name}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Queue: ${controller.queueLabel}',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      if (controller.upNextTracks.isNotEmpty)
                        for (final track in controller.upNextTracks.take(2)) ...[
                          _QueuePreview(track: track),
                          const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
                        ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RailNavigation extends StatelessWidget {
  const _RailNavigation({required this.controller});

  final MonolithController controller;

  @override
  Widget build(BuildContext context) {
    final selected = AppTab.values.indexOf(controller.currentTab);
    return GlassPanel(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: NavigationRail(
        selectedIndex: selected,
        onDestinationSelected: (index) =>
            controller.selectTab(AppTab.values[index]),
        labelType: NavigationRailLabelType.all,
        destinations: [
          NavigationRailDestination(
            icon: PhosphorIcon(AppIcons.navLibrary(false), size: 26),
            selectedIcon: PhosphorIcon(AppIcons.navLibrary(true), size: 26),
            label: const Text('Library'),
          ),
          NavigationRailDestination(
            icon: PhosphorIcon(AppIcons.navDownloads(false), size: 26),
            selectedIcon: PhosphorIcon(AppIcons.navDownloads(true), size: 26),
            label: const Text('Downloads'),
          ),
          NavigationRailDestination(
            icon: PhosphorIcon(AppIcons.navSearch(false), size: 26),
            selectedIcon: PhosphorIcon(AppIcons.navSearch(true), size: 26),
            label: const Text('Search'),
          ),
        ],
      ),
    );
  }
}

class _BottomNavigation extends StatelessWidget {
  const _BottomNavigation({required this.controller});

  final MonolithController controller;

  @override
  Widget build(BuildContext context) {
    final selected = AppTab.values.indexOf(controller.currentTab);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.sm + AppSpacing.xs,
        ),
        child: GlassPanel(
          child: NavigationBar(
            selectedIndex: selected,
            height: 72,
            onDestinationSelected: (index) =>
                controller.selectTab(AppTab.values[index]),
            destinations: [
              NavigationDestination(
                icon: PhosphorIcon(
                  AppIcons.navLibrary(false),
                  key: const Key('nav-library-icon'),
                  size: 26,
                ),
                selectedIcon: PhosphorIcon(AppIcons.navLibrary(true), size: 26),
                label: 'Library',
              ),
              NavigationDestination(
                icon: PhosphorIcon(
                  AppIcons.navDownloads(false),
                  key: const Key('nav-downloads-icon'),
                  size: 26,
                ),
                selectedIcon:
                    PhosphorIcon(AppIcons.navDownloads(true), size: 26),
                label: 'Downloads',
              ),
              NavigationDestination(
                icon: PhosphorIcon(
                  AppIcons.navSearch(false),
                  key: const Key('nav-search-icon'),
                  size: 26,
                ),
                selectedIcon: PhosphorIcon(AppIcons.navSearch(true), size: 26),
                label: 'Search',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer({required this.controller});

  final MonolithController controller;

  @override
  Widget build(BuildContext context) {
    final track = controller.currentTrack;
    final scheme = Theme.of(context).colorScheme;

    return GlassPanel(
      key: const Key('mini-player'),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: controller.openPlayer,
          borderRadius: AppRadii.all(AppRadii.lg),
          child: Row(
            children: [
              SizedBox(
                width: 56,
                height: 56,
                child: Hero(
                  tag: 'player-artwork-${track.id}',
                  child: TrackArtwork(
                    track: track,
                    borderRadius: AppRadii.all(AppRadii.md),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: track.canPlay ? controller.togglePlayback : null,
                icon: PhosphorIcon(
                  controller.isPlaying ? AppIcons.pauseCircle : AppIcons.playCircle,
                  color: scheme.primary,
                  size: 36,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerOverlay extends StatelessWidget {
  const _PlayerOverlay({
    super.key,
    required this.controller,
    required this.animation,
    required this.artworkAnimation,
    required this.wideLayout,
  });

  final MonolithController controller;
  final Animation<double> animation;
  final Animation<double> artworkAnimation;
  final bool wideLayout;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final height = MediaQuery.sizeOf(context).height;
    final panelHeight = wideLayout
        ? (height * 0.82).clamp(520.0, 760.0)
        : (height * 0.9).clamp(480.0, 860.0);

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: controller.closePlayer,
            child: ColoredBox(
              color: Colors.black.withValues(alpha: 0.32),
            ),
          ),
        ),
        SafeArea(
          child: Align(
            alignment:
                wideLayout ? Alignment.center : Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                wideLayout ? AppSpacing.xxl : AppSpacing.sm + AppSpacing.xs,
                wideLayout ? AppSpacing.xl : AppSpacing.sm + AppSpacing.xs,
                wideLayout ? AppSpacing.xxl : AppSpacing.sm + AppSpacing.xs,
                wideLayout ? AppSpacing.xl : 0,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: wideLayout ? 520 : 480,
                  maxHeight: panelHeight,
                ),
                child: Material(
                  key: const Key('player-overlay-sheet'),
                  color: scheme.surface.withValues(alpha: 0.96),
                  elevation: 28,
                  borderRadius: AppRadii.all(AppRadii.xl),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          AppSpacing.md,
                          AppSpacing.md,
                          AppSpacing.sm,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 42,
                                    height: 4,
                                    margin: const EdgeInsets.only(
                                      bottom: AppSpacing.md,
                                    ),
                                    decoration: BoxDecoration(
                                      color: scheme.outlineVariant,
                                      borderRadius: AppRadii.all(AppRadii.pill),
                                    ),
                                  ),
                                  Text(
                                    'Now playing',
                                    style: textTheme.titleLarge,
                                  ),
                                  Text(
                                    'Opened from the mini deck',
                                    style: textTheme.bodyMedium?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              key: const Key('player-overlay-close'),
                              onPressed: controller.closePlayer,
                              icon: PhosphorIcon(AppIcons.close),
                              tooltip: 'Close player',
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: PlayerPage(
                          animation: animation,
                          artworkAnimation: artworkAnimation,
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.screenInset,
                            AppSpacing.sm,
                            AppSpacing.screenInset,
                            AppSpacing.xxl,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _QueuePreview extends StatelessWidget {
  const _QueuePreview({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 48,
          height: 48,
          child: TrackArtwork(
            track: track,
            borderRadius: AppRadii.all(AppRadii.sm),
          ),
        ),
        const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
