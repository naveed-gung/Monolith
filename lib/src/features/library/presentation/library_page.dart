import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/state/app_controller.dart';
import '../../../app/state/app_scope.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../core/models/music_models.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/track_artwork.dart';
import '../../../shared/widgets/app_download_indicator.dart';

enum _SortOrder { aToZ, zToA, newest, oldest }

enum _TrackAction { edit, delete, addToPlaylist, share, removeFromPlaylist }

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, this.onOpenSettings, this.onSwipeToNextTab});
  final VoidCallback? onOpenSettings;
  final VoidCallback? onSwipeToNextTab;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  _SortOrder _sortOrder = _SortOrder.aToZ;
  // Non-null when user has drilled into an artist / album / playlist
  String? _drillItem;

  // ── Smart (virtual) playlists ─────────────────────────────────────────────
  static const _smartRecent = 'Recently added';
  static const _smartMost = 'Most played';
  static const _smartNever = 'Never played';
  static const _smartNames = [_smartRecent, _smartMost, _smartNever];

  /// Returns the computed track list for a smart-playlist name, or null if the
  /// name isn't a smart playlist.
  List<Track>? _smartListFor(MonolithController controller, String name) {
    switch (name) {
      case _smartRecent:
        return controller.recentlyAdded;
      case _smartMost:
        return controller.mostPlayed;
      case _smartNever:
        return controller.neverPlayed;
    }
    return null;
  }

  // ── Sort helpers ────────────────────────────────────────────────────────

  List<Track> _sortedTracks(List<Track> src) {
    final list = [...src];
    switch (_sortOrder) {
      case _SortOrder.aToZ:
        list.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
      case _SortOrder.zToA:
        list.sort(
          (a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()),
        );
      case _SortOrder.newest:
        return list.reversed.toList();
      case _SortOrder.oldest:
        break; // keep insertion order
    }
    return list;
  }

  List<String> _sortedStrings(List<String> src) {
    final list = [...src];
    switch (_sortOrder) {
      case _SortOrder.aToZ:
        list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      case _SortOrder.zToA:
        list.sort((a, b) => b.toLowerCase().compareTo(a.toLowerCase()));
      case _SortOrder.newest:
        return list.reversed.toList();
      case _SortOrder.oldest:
        break;
    }
    return list;
  }

  // ── Track actions ────────────────────────────────────────────────────────

  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _editTrack(Track track, MonolithController controller) async {
    final titleC = TextEditingController(text: track.title);
    final artistC = TextEditingController(text: track.artist);
    final albumC = TextEditingController(text: track.album);
    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleC,
              decoration: const InputDecoration(labelText: 'Title'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: artistC,
              decoration: const InputDecoration(labelText: 'Artist'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: albumC,
              decoration: const InputDecoration(labelText: 'Album'),
              textCapitalization: TextCapitalization.words,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final t = titleC.text;
    final a = artistC.text;
    final al = albumC.text;
    if (save != true || !mounted) return;
    _showMsg(
      await controller.renameTrackMetadata(
        track: track,
        title: t,
        artist: a,
        album: al,
      ),
    );
  }

  Future<void> _deleteTrack(Track track, MonolithController controller) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove track'),
        content: Text('Remove ${track.title} from your library?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    _showMsg(await controller.deleteTrack(track));
  }

  Future<void> _addToPlaylist(
    Track track,
    MonolithController controller,
  ) async {
    final playlistC = TextEditingController();
    final name = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      // Let the sheet grow taller than half-screen and ride above the
      // keyboard: viewInsets padding lifts the text field clear of it.
      isScrollControlled: true,
      builder: (ctx) => AnimatedPadding(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenInset,
            AppSpacing.sm,
            AppSpacing.screenInset,
            AppSpacing.xxl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add to playlist',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.md),
              if (controller.playlistNames.isNotEmpty)
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final n in controller.playlistNames)
                      ActionChip(
                        label: Text(n),
                        onPressed: () => Navigator.pop(ctx, n),
                      ),
                  ],
                ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: playlistC,
                decoration: const InputDecoration(
                  labelText: 'New playlist name',
                  hintText: 'Night drive mix',
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () =>
                          Navigator.pop(ctx, playlistC.text.trim()),
                      icon: PhosphorIcon(AppIcons.plusCircle, size: 18),
                      label: const Text('Create & add'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    _showMsg(controller.addTrackToPlaylist(track: track, playlistName: name));
  }

  Future<void> _shareTrack(Track track) async {
    try {
      final fp = track.filePath;
      if (fp != null && fp.trim().isNotEmpty) {
        await Share.shareXFiles([
          XFile(fp),
        ], text: '${track.title} • ${track.artist}');
      } else {
        await Share.share('${track.title} • ${track.artist}');
      }
    } catch (e) {
      _showMsg('Sharing failed: $e');
    }
  }

  Future<void> _openMenu(
    Track track,
    MonolithController controller, {
    String? playlistContext,
  }) async {
    final action = await showModalBottomSheet<_TrackAction>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: PhosphorIcon(AppIcons.edit),
              title: const Text('Edit details'),
              onTap: () => Navigator.pop(ctx, _TrackAction.edit),
            ),
            ListTile(
              leading: PhosphorIcon(AppIcons.addToPlaylist),
              title: const Text('Add to playlist'),
              onTap: () => Navigator.pop(ctx, _TrackAction.addToPlaylist),
            ),
            ListTile(
              leading: PhosphorIcon(AppIcons.share),
              title: const Text('Share'),
              onTap: () => Navigator.pop(ctx, _TrackAction.share),
            ),
            if (playlistContext != null)
              ListTile(
                leading: PhosphorIcon(AppIcons.delete),
                title: const Text('Remove from playlist'),
                onTap: () =>
                    Navigator.pop(ctx, _TrackAction.removeFromPlaylist),
              ),
            ListTile(
              leading: PhosphorIcon(AppIcons.delete),
              title: const Text('Delete'),
              onTap: () => Navigator.pop(ctx, _TrackAction.delete),
            ),
          ],
        ),
      ),
    );
    switch (action) {
      case _TrackAction.edit:
        await _editTrack(track, controller);
      case _TrackAction.delete:
        await _deleteTrack(track, controller);
      case _TrackAction.addToPlaylist:
        await _addToPlaylist(track, controller);
      case _TrackAction.share:
        await _shareTrack(track);
      case _TrackAction.removeFromPlaylist:
        if (playlistContext != null) {
          _showMsg(
            controller.removeTrackFromPlaylist(
              track: track,
              playlistName: playlistContext,
            ),
          );
        }
      case null:
        return;
    }
  }

  // ── Create playlist ───────────────────────────────────────────────────────

  Future<void> _createPlaylist(MonolithController controller) async {
    final nameC = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New playlist'),
        content: TextField(
          controller: nameC,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Playlist name',
            hintText: 'Night drive mix',
          ),
          textCapitalization: TextCapitalization.words,
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, nameC.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    controller.createEmptyPlaylist(name);
    _showMsg('Created playlist "$name".');
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isLight = Theme.of(context).brightness == Brightness.light;

    // When drilling into a category item, compute which tracks to show
    Widget contentSliver;
    if (_drillItem != null) {
      final cat = controller.selectedCategory;
      final List<Track> drillTracks;
      if (cat == LibraryCategory.artists) {
        drillTracks = _sortedTracks(
          controller.tracks.where((t) => t.artist == _drillItem).toList(),
        );
      } else if (cat == LibraryCategory.albums) {
        drillTracks = _sortedTracks(
          controller.tracks.where((t) => t.album == _drillItem).toList(),
        );
      } else if (cat == LibraryCategory.playlists) {
        // Smart virtual playlists keep their intrinsic order; real playlists
        // honour the chosen sort. Real playlists win on a name clash.
        final smart = controller.playlistNames.contains(_drillItem)
            ? null
            : _smartListFor(controller, _drillItem!);
        drillTracks =
            smart ?? _sortedTracks(controller.tracksForPlaylist(_drillItem!));
      } else {
        drillTracks = const [];
      }

      final isSmartDrill =
          cat == LibraryCategory.playlists &&
          !controller.playlistNames.contains(_drillItem) &&
          _smartNames.contains(_drillItem);

      contentSliver = _DrillTrackList(
        title: _drillItem!,
        tracks: drillTracks,
        controller: controller,
        playlistContext: (cat == LibraryCategory.playlists && !isSmartDrill)
            ? _drillItem
            : null,
        onBack: () => setState(() => _drillItem = null),
        onMenu: (t, {String? playlistContext}) =>
            _openMenu(t, controller, playlistContext: playlistContext),
      );
    } else {
      final sortBtn = PopupMenuButton<_SortOrder>(
        tooltip: 'Sort',
        padding: EdgeInsets.zero,
        icon: PhosphorIcon(
          PhosphorIcons.arrowsDownUp(),
          size: 18,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        initialValue: _sortOrder,
        onSelected: (o) => setState(() => _sortOrder = o),
        itemBuilder: (_) => const [
          PopupMenuItem(value: _SortOrder.aToZ, child: Text('A → Z')),
          PopupMenuItem(value: _SortOrder.zToA, child: Text('Z → A')),
          PopupMenuItem(value: _SortOrder.newest, child: Text('Newest first')),
          PopupMenuItem(value: _SortOrder.oldest, child: Text('Oldest first')),
        ],
      );
      contentSliver = switch (controller.selectedCategory) {
        LibraryCategory.tracks => _TracksSilver(
          controller: controller,
          sortedTracks: _sortedTracks(controller.tracks),
          sortedHighlights: _sortedTracks(controller.highlightedTracks),
          onMenu: (t) => _openMenu(t, controller),
          sortButton: sortBtn,
        ),
        LibraryCategory.artists => _ArtistSliver(
          controller: controller,
          sortedArtists: _sortedStrings(controller.libraryArtists),
          onDrillIn: (name) => setState(() => _drillItem = name),
          sortButton: sortBtn,
        ),
        LibraryCategory.albums => _AlbumSliver(
          controller: controller,
          sortedHighlights: _sortedTracks(controller.albumHighlights),
          onDrillIn: (name) => setState(() => _drillItem = name),
          sortButton: sortBtn,
        ),
        LibraryCategory.playlists => _PlaylistSliver(
          controller: controller,
          sortedPlaylists: _sortedStrings(controller.playlistNames),
          smartPlaylists: {
            _smartRecent: controller.recentlyAdded.length,
            _smartMost: controller.mostPlayed.length,
            _smartNever: controller.neverPlayed.length,
          },
          onDrillIn: (name) => setState(() => _drillItem = name),
          onCreatePlaylist: () => _createPlaylist(controller),
          sortButton: sortBtn,
        ),
      };
    }

    final categories = LibraryCategory.values;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -250) {
          // Swiped left -> advance sub-tab, or at end switch to next screen
          final curIndex = categories.indexOf(controller.selectedCategory);
          if (curIndex < categories.length - 1) {
            controller.hapticLight();
            setState(() => _drillItem = null);
            controller.selectLibraryCategory(categories[curIndex + 1]);
          } else {
            widget.onSwipeToNextTab?.call();
          }
        } else if (velocity > 250) {
          // Swiped right -> reverse sub-tab or exit drill-in
          if (_drillItem != null) {
            controller.hapticLight();
            setState(() => _drillItem = null);
          } else {
            final curIndex = categories.indexOf(controller.selectedCategory);
            if (curIndex > 0) {
              controller.hapticLight();
              controller.selectLibraryCategory(categories[curIndex - 1]);
            }
          }
        }
      },
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 24),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'MONOLITH',
                          style: textTheme.labelSmall?.copyWith(
                            letterSpacing: 2.4,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Your library',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.headlineLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            letterSpacing: -1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          controller.isLibraryLoading
                              ? 'Finding your music…'
                              : '${controller.tracks.length} ${controller.tracks.length == 1 ? 'song' : 'songs'} · On this device',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const AppDownloadIndicator(),
                  Theme(
                    data: Theme.of(context).copyWith(
                      popupMenuTheme: PopupMenuThemeData(
                        color: isLight ? Colors.white : const Color(0xFF161A24),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: isLight
                                ? Colors.black.withValues(alpha: 0.08)
                                : Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                        elevation: 12,
                      ),
                    ),
                    child: PopupMenuButton<String>(
                      tooltip: 'Import music',
                      offset: const Offset(0, 42),
                      elevation: 8,
                      icon: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: isLight
                              ? Colors.black.withValues(alpha: 0.04)
                              : Colors.white.withValues(alpha: 0.06),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isLight
                                ? Colors.black.withValues(alpha: 0.06)
                                : Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Icon(
                          Icons.add_rounded,
                          size: 20,
                          color: scheme.onSurface,
                        ),
                      ),
                      onSelected: (source) async {
                        final String? message;
                        if (source == 'music_all') {
                          message = await controller.importAllFromMusicLibrary();
                        } else if (source == 'music') {
                          message = await controller.importFromMusicLibrary();
                        } else {
                          message = await controller.importAudioFiles();
                        }
                        if (message != null) _showMsg(message);
                      },
                      itemBuilder: (_) => [
                        if (controller.supportsAppleMusicImportPrompt) ...[
                          PopupMenuItem(
                            value: 'music_all',
                            height: 44,
                            child: Row(
                              children: [
                                PhosphorIcon(
                                  PhosphorIcons.musicNotesSimple(),
                                  size: 18,
                                  color: scheme.primary,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Import All from Music',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: scheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'music',
                            height: 44,
                            child: Row(
                              children: [
                                PhosphorIcon(
                                  PhosphorIcons.checkSquareOffset(),
                                  size: 18,
                                  color: scheme.primary,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Select from Music…',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: scheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        PopupMenuItem(
                          value: 'files',
                          height: 44,
                          child: Row(
                            children: [
                              PhosphorIcon(
                                PhosphorIcons.folderSimple(),
                                size: 18,
                                color: scheme.primary,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'From Files',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: scheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const Key('settings-button'),
                    onPressed: widget.onOpenSettings,
                    tooltip: 'Settings',
                    icon: PhosphorIcon(AppIcons.settings, size: 22),
                  ),
                ],
              ),
            ),
          ),
          // ── Library error banner ─────────────────────────────────────
          if (controller.libraryError != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenInset,
                  AppSpacing.lg,
                  AppSpacing.screenInset,
                  0,
                ),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.sm,
                    AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: AppRadii.all(AppRadii.md),
                  ),
                  child: Row(
                    children: [
                      PhosphorIcon(
                        PhosphorIcons.warning(),
                        size: 18,
                        color: scheme.error,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          controller.libraryError!,
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onErrorContainer,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => controller.refreshLibrary(
                          retryPermissionRequest: true,
                        ),
                        child: const Text('Retry'),
                      ),
                      IconButton(
                        icon: PhosphorIcon(AppIcons.close, size: 16),
                        color: scheme.onErrorContainer,
                        tooltip: 'Dismiss',
                        onPressed: () => controller.clearLibraryError(),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          if (controller.tracks.isNotEmpty && _drillItem == null)
            SliverToBoxAdapter(child: _RecentShelf(controller: controller)),
          if (controller.tracks.isEmpty && !controller.isLibraryLoading)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 32,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.library_music_outlined,
                      size: 40,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Make room for your favorites.',
                      style: textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Bring songs from Music or Files. Your collection stays on your phone.',
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: () async {
                        final message = await controller.importAudioFiles();
                        if (message != null) _showMsg(message);
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Import songs'),
                    ),
                  ],
                ),
              ),
            ),
          // ── Category selector ─────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenInset,
                AppSpacing.xxl,
                AppSpacing.screenInset,
                0,
              ),
              child: _CategoryTabs(
                selected: controller.selectedCategory,
                onSelected: (cat) {
                  setState(() => _drillItem = null);
                  controller.selectLibraryCategory(cat);
                },
              ),
            ),
          ),

          // ── Content ───────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenInset,
              AppSpacing.md,
              AppSpacing.screenInset,
              180,
            ),
            sliver: contentSliver,
          ),
        ],
      ),
    );
  }
}

// ── Now Playing Hero ────────────────────────────────────────────────────────

class _RecentShelf extends StatelessWidget {
  const _RecentShelf({required this.controller});
  final MonolithController controller;
  @override
  Widget build(BuildContext context) {
    final tracks = [...controller.tracks]
      ..sort(
        (a, b) =>
            (b.addedAt ?? DateTime(0)).compareTo(a.addedAt ?? DateTime(0)),
      );
    final recent = tracks.take(8).toList();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text('Recently added', style: theme.textTheme.titleMedium),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 160 + MediaQuery.textScalerOf(context).scale(30),
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            scrollDirection: Axis.horizontal,
            itemCount: recent.length,
            separatorBuilder: (_, _) => const SizedBox(width: 16),
            itemBuilder: (context, i) {
              final track = recent[i];
              return SizedBox(
                width: 132,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => controller.selectTrack(track, openPlayer: true),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox.square(
                        dimension: 132,
                        child: TrackArtwork(
                          track: track,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CategoryTabs extends StatelessWidget {
  const _CategoryTabs({required this.selected, required this.onSelected});
  final LibraryCategory selected;
  final ValueChanged<LibraryCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    const labels = {
      LibraryCategory.tracks: 'Tracks',
      LibraryCategory.artists: 'Artists',
      LibraryCategory.albums: 'Albums',
      LibraryCategory.playlists: 'Playlists',
    };

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final entry in labels.entries)
            Semantics(
              selected: entry.key == selected,
              child: InkWell(
                onTap: () => onSelected(entry.key),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: entry.key == selected
                            ? scheme.onSurface
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Text(
                    entry.value,
                    style: textTheme.titleSmall?.copyWith(
                      color: entry.key == selected
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant,
                      fontWeight: entry.key == selected
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Drill-down track list ────────────────────────────────────────────────────

class _DrillTrackList extends StatelessWidget {
  const _DrillTrackList({
    required this.title,
    required this.tracks,
    required this.controller,
    required this.onBack,
    required this.onMenu,
    this.playlistContext,
  });

  final String title;
  final List<Track> tracks;
  final MonolithController controller;
  final VoidCallback onBack;
  final Future<void> Function(Track, {String? playlistContext}) onMenu;
  final String? playlistContext;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        // index 0: back header
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            child: Row(
              children: [
                IconButton(
                  onPressed: onBack,
                  icon: PhosphorIcon(PhosphorIcons.caretLeft(), size: 22),
                  color: scheme.primary,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleLarge?.copyWith(
                          fontWeight: AppType.title,
                        ),
                      ),
                      Text(
                        '${tracks.length} track${tracks.length == 1 ? '' : 's'}',
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        if (tracks.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
            child: Center(
              child: Text(
                'No tracks here yet',
                style: textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        }

        final track = tracks[index - 1];
        final isLast = index == tracks.length;
        return Column(
          children: [
            _TrackRow(
              track: track,
              isActive: controller.currentTrack?.id == track.id,
              onTap: () => controller.selectTrack(track, openPlayer: true),
              onMenu: () => onMenu(track, playlistContext: playlistContext),
            ),
            if (!isLast)
              Divider(
                height: 1,
                indent: 72,
                color: scheme.outlineVariant.withValues(alpha: 0.35),
              ),
          ],
        );
      }, childCount: tracks.isEmpty ? 2 : tracks.length + 1),
    );
  }
}

// ── Tracks sliver ─────────────────────────────────────────────────────────────

class _TracksSilver extends StatelessWidget {
  const _TracksSilver({
    required this.controller,
    required this.sortedTracks,
    required this.sortedHighlights,
    required this.onMenu,
    this.sortButton,
  });

  final MonolithController controller;
  final List<Track> sortedTracks;
  final List<Track> sortedHighlights;
  final Future<void> Function(Track) onMenu;
  final Widget? sortButton;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (controller.isLibraryLoading) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xxxl),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final totalCount = 1 + sortedTracks.length;

    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: SectionHeader(
              title: 'All songs',
              actionLabel: '${sortedTracks.length} total',
              trailing: sortButton,
            ),
          );
        }
        if (index <= sortedTracks.length) {
          final track = sortedTracks[index - 1];
          final isLast = index == sortedTracks.length;
          return Column(
            children: [
              _TrackRow(
                track: track,
                isActive: controller.currentTrack?.id == track.id,
                onTap: () => controller.selectTrack(track, openPlayer: true),
                onMenu: () => onMenu(track),
              ),
              if (!isLast)
                Divider(
                  height: 1,
                  indent: 72,
                  color: scheme.outlineVariant.withValues(alpha: 0.35),
                ),
            ],
          );
        }
        return const SizedBox.shrink();
      }, childCount: totalCount),
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.track,
    required this.isActive,
    required this.onTap,
    required this.onMenu,
  });

  final Track track;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.sm + AppSpacing.xs,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              height: 52,
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
                    style: textTheme.bodyLarge?.copyWith(
                      fontWeight: isActive ? AppType.title : AppType.body,
                      color: isActive ? scheme.primary : null,
                    ),
                  ),
                  Text(
                    '${track.artist} • ${track.album}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              track.duration > Duration.zero
                  ? '${track.duration.inMinutes}:${track.duration.inSeconds.remainder(60).toString().padLeft(2, '0')}'
                  : '—',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            IconButton(
              onPressed: onMenu,
              icon: PhosphorIcon(AppIcons.more, size: 20),
              color: scheme.onSurfaceVariant,
              padding: const EdgeInsets.all(AppSpacing.sm),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Album card ───────────────────────────────────────────────────────────────

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({required this.track, required this.onTap});
  final Track track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: AppRadii.all(AppRadii.lg),
            child: AspectRatio(
              aspectRatio: 1,
              child: TrackArtwork(
                track: track,
                borderRadius: AppRadii.all(AppRadii.lg),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
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
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ── Artist sliver ─────────────────────────────────────────────────────────────

class _ArtistSliver extends StatelessWidget {
  const _ArtistSliver({
    required this.controller,
    required this.sortedArtists,
    required this.onDrillIn,
    this.sortButton,
  });

  final MonolithController controller;
  final List<String> sortedArtists;
  final ValueChanged<String> onDrillIn;
  final Widget? sortButton;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: SectionHeader(title: 'Artists', trailing: sortButton),
          );
        }
        final artist = sortedArtists[index - 1];
        final trackCount = controller.tracks
            .where((t) => t.artist == artist)
            .length;
        final isLast = index == sortedArtists.length;

        return Column(
          children: [
            InkWell(
              onTap: () => onDrillIn(artist),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: scheme.primaryContainer,
                      child: Text(
                        artist.isNotEmpty
                            ? artist.substring(0, 1).toUpperCase()
                            : '?',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: scheme.onPrimaryContainer,
                              fontWeight: AppType.label,
                            ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            artist,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(fontWeight: AppType.body),
                          ),
                          Text(
                            '$trackCount track${trackCount == 1 ? '' : 's'}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
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
            ),
            if (!isLast)
              Divider(
                height: 1,
                indent: 60,
                color: scheme.outlineVariant.withValues(alpha: 0.35),
              ),
          ],
        );
      }, childCount: sortedArtists.length + 1),
    );
  }
}

// ── Albums sliver ─────────────────────────────────────────────────────────────

class _AlbumSliver extends StatelessWidget {
  const _AlbumSliver({
    required this.controller,
    required this.sortedHighlights,
    required this.onDrillIn,
    this.sortButton,
  });

  final MonolithController controller;
  final List<Track> sortedHighlights;
  final ValueChanged<String> onDrillIn;
  final Widget? sortButton;

  @override
  Widget build(BuildContext context) {
    final rows = (sortedHighlights.length / 2).ceil();

    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            child: SectionHeader(title: 'Albums', trailing: sortButton),
          );
        }
        final row = index - 1;
        if (row >= rows) return null;
        final a = sortedHighlights[row * 2];
        final b = row * 2 + 1 < sortedHighlights.length
            ? sortedHighlights[row * 2 + 1]
            : null;
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _AlbumCard(track: a, onTap: () => onDrillIn(a.album)),
              ),
              if (b != null) ...[
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _AlbumCard(track: b, onTap: () => onDrillIn(b.album)),
                ),
              ] else
                const Expanded(child: SizedBox()),
            ],
          ),
        );
      }, childCount: rows + 1),
    );
  }
}

// ── Playlists sliver ─────────────────────────────────────────────────────────

class _PlaylistSliver extends StatelessWidget {
  const _PlaylistSliver({
    required this.controller,
    required this.sortedPlaylists,
    required this.smartPlaylists,
    required this.onDrillIn,
    required this.onCreatePlaylist,
    this.sortButton,
  });

  final MonolithController controller;
  final List<String> sortedPlaylists;
  final Map<String, int> smartPlaylists; // name -> track count
  final ValueChanged<String> onDrillIn;
  final VoidCallback onCreatePlaylist;
  final Widget? sortButton;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        // index 0: header + create button
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Row(
              children: [
                const Expanded(child: SectionHeader(title: 'Playlists')),
                ?sortButton,
                FilledButton.icon(
                  onPressed: onCreatePlaylist,
                  icon: PhosphorIcon(AppIcons.plusCircle, size: 16),
                  label: const Text('New'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xs,
                    ),
                    minimumSize: const Size(0, 32),
                    textStyle: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              ],
            ),
          );
        }
        // index 1: pinned Smart playlists group
        if (index == 1) {
          final icons = <String, PhosphorIconData>{
            'Recently added': PhosphorIcons.clock(),
            'Most played': PhosphorIcons.chartBar(),
            'Never played': PhosphorIcons.sparkle(),
          };
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text(
                    'SMART',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: AppType.label,
                      letterSpacing: AppType.trackWide,
                    ),
                  ),
                ),
                for (final entry in smartPlaylists.entries)
                  InkWell(
                    onTap: () => onDrillIn(entry.key),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.sm,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              borderRadius: AppRadii.all(AppRadii.md),
                            ),
                            child: Center(
                              child: PhosphorIcon(
                                icons[entry.key] ?? AppIcons.queue,
                                size: 20,
                                color: scheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entry.key,
                                  style: Theme.of(context).textTheme.bodyLarge
                                      ?.copyWith(fontWeight: AppType.body),
                                ),
                                Text(
                                  entry.value == 1
                                      ? '1 track'
                                      : '${entry.value} tracks',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
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
                  ),
              ],
            ),
          );
        }
        if (sortedPlaylists.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
            child: Center(
              child: Text(
                'No playlists yet — tap New to create one',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        }
        final name = sortedPlaylists[index - 2];
        final tracks = controller.tracksForPlaylist(name);
        final lead = controller.leadTrackForPlaylist(name);
        final isLast = index == sortedPlaylists.length + 1;

        return Column(
          children: [
            InkWell(
              onTap: () => onDrillIn(name),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Row(
                  children: [
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: lead == null
                          ? Container(
                              decoration: BoxDecoration(
                                color: scheme.primaryContainer,
                                borderRadius: AppRadii.all(AppRadii.md),
                              ),
                              child: PhosphorIcon(
                                AppIcons.queue,
                                color: scheme.onPrimaryContainer,
                              ),
                            )
                          : TrackArtwork(
                              track: lead,
                              borderRadius: AppRadii.all(AppRadii.md),
                            ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(fontWeight: AppType.body),
                          ),
                          Text(
                            tracks.isEmpty
                                ? 'Empty'
                                : '${tracks.length} track${tracks.length == 1 ? '' : 's'}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
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
            ),
            if (!isLast)
              Divider(
                height: 1,
                indent: 72,
                color: scheme.outlineVariant.withValues(alpha: 0.35),
              ),
          ],
        );
      }, childCount: sortedPlaylists.isEmpty ? 3 : sortedPlaylists.length + 2),
    );
  }
}
