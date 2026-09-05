import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/state/app_controller.dart';
import '../../../app/state/app_scope.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../core/models/music_models.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/track_artwork.dart';

enum _SongsSortOrder { aToZ, zToA, newest, oldest }

enum _TrackAction { edit, addToPlaylist, share, delete }

class SongsPage extends StatefulWidget {
  const SongsPage({super.key});

  @override
  State<SongsPage> createState() => _SongsPageState();
}

class _SongsPageState extends State<SongsPage> {
  final TextEditingController _searchController = TextEditingController();
  _SongsSortOrder _sortOrder = _SongsSortOrder.newest;
  String _filterQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      final query = _searchController.text.trim().toLowerCase();
      if (query != _filterQuery) {
        setState(() => _filterQuery = query);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Track> _filterAndSort(List<Track> rawTracks) {
    var list = rawTracks;
    if (_filterQuery.isNotEmpty) {
      list = list.where((t) {
        return t.title.toLowerCase().contains(_filterQuery) ||
            t.artist.toLowerCase().contains(_filterQuery) ||
            t.album.toLowerCase().contains(_filterQuery);
      }).toList();
    } else {
      list = [...list];
    }

    switch (_sortOrder) {
      case _SongsSortOrder.aToZ:
        list.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
      case _SongsSortOrder.zToA:
        list.sort(
          (a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()),
        );
      case _SongsSortOrder.newest:
        list.sort((a, b) {
          final aDate = a.addedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = b.addedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bDate.compareTo(aDate);
        });
      case _SongsSortOrder.oldest:
        list.sort((a, b) {
          final aDate = a.addedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = b.addedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return aDate.compareTo(bDate);
        });
    }
    return list;
  }

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
        title: const Text('Edit song details'),
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
    if (save != true || !mounted) return;
    _showMsg(
      await controller.renameTrackMetadata(
        track: track,
        title: titleC.text,
        artist: artistC.text,
        album: albumC.text,
      ),
    );
  }

  Future<void> _deleteTrack(Track track, MonolithController controller) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete song'),
        content: Text('Delete "${track.title}" from your library?'),
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

  Future<void> _openMenu(Track track, MonolithController controller) async {
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
      case _TrackAction.share:
        await _shareTrack(track);
      case _TrackAction.addToPlaylist:
        if (!mounted) return;
        final playlistC = TextEditingController();
        final name = await showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (ctx) => AnimatedPadding(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(ctx).bottom,
            ),
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
                      hintText: 'Favorites',
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
        if (name != null && name.isNotEmpty && mounted) {
          _showMsg(
            controller.addTrackToPlaylist(track: track, playlistName: name),
          );
        }
      case null:
        break;
    }
  }

  String _formatDuration(Duration d) {
    if (d == Duration.zero) return '--:--';
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tracks = _filterAndSort(controller.tracks);

    return RefreshIndicator(
      onRefresh: () => controller.refreshLibrary(retryPermissionRequest: true),
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          // Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenInset,
                AppSpacing.xl,
                AppSpacing.screenInset,
                AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        margin: const EdgeInsets.only(right: AppSpacing.md),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: AppRadii.all(AppRadii.md),
                        ),
                        child: PhosphorIcon(
                          PhosphorIcons.musicNotes(PhosphorIconsStyle.fill),
                          color: scheme.onPrimary,
                          size: 22,
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Songs',
                              style: textTheme.displaySmall?.copyWith(
                                fontWeight: AppType.display,
                                letterSpacing: AppType.trackTight,
                              ),
                            ),
                            Text(
                              '${tracks.length} ${tracks.length == 1 ? 'song' : 'songs'}',
                              style: textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuButton<_SongsSortOrder>(
                        tooltip: 'Sort songs',
                        icon: PhosphorIcon(
                          PhosphorIcons.arrowsDownUp(),
                          size: 20,
                          color: scheme.onSurfaceVariant,
                        ),
                        initialValue: _sortOrder,
                        onSelected: (order) =>
                            setState(() => _sortOrder = order),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: _SongsSortOrder.newest,
                            child: Text('Newest added'),
                          ),
                          PopupMenuItem(
                            value: _SongsSortOrder.oldest,
                            child: Text('Oldest added'),
                          ),
                          PopupMenuItem(
                            value: _SongsSortOrder.aToZ,
                            child: Text('A → Z'),
                          ),
                          PopupMenuItem(
                            value: _SongsSortOrder.zToA,
                            child: Text('Z → A'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // Search & Shuffle row
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Search songs…',
                            prefixIcon: PhosphorIcon(
                              PhosphorIcons.magnifyingGlass(),
                              size: 18,
                              color: scheme.onSurfaceVariant,
                            ),
                            suffixIcon: _filterQuery.isNotEmpty
                                ? IconButton(
                                    icon: PhosphorIcon(
                                      PhosphorIcons.x(),
                                      size: 16,
                                    ),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _filterQuery = '');
                                    },
                                  )
                                : null,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical: AppSpacing.sm,
                            ),
                            filled: true,
                            fillColor: scheme.surfaceContainerHigh.withValues(
                              alpha: 0.6,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: AppRadii.all(AppRadii.pill),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      if (tracks.isNotEmpty) ...[
                        const SizedBox(width: AppSpacing.sm),
                        FilledButton.tonalIcon(
                          onPressed: () {
                            controller.hapticMedium();
                            final shuffled = [...tracks]..shuffle();
                            if (shuffled.isNotEmpty) {
                              controller.selectTrack(
                                shuffled.first,
                                autoplay: true,
                                openPlayer: true,
                              );
                            }
                          },
                          icon: PhosphorIcon(AppIcons.shuffle, size: 18),
                          label: const Text('Shuffle'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical: 10,
                            ),
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.all(
                                Radius.circular(AppRadii.pill),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Songs List
          if (tracks.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xxl),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      PhosphorIcon(
                        PhosphorIcons.musicNotes(),
                        size: 48,
                        color: scheme.outline,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        _filterQuery.isNotEmpty
                            ? 'No songs matching "$_filterQuery"'
                            : 'No songs in your library yet',
                        textAlign: TextAlign.center,
                        style: textTheme.bodyLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Download songs or import them from Settings.',
                        textAlign: TextAlign.center,
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenInset,
                AppSpacing.xs,
                AppSpacing.screenInset,
                180,
              ),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final track = tracks[index];
                    final isCurrent = controller.currentTrack?.id == track.id;
                    final isPlaying = isCurrent && controller.isPlaying;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: InkWell(
                        onTap: () {
                          controller.hapticLight();
                          controller.selectTrack(
                            track,
                            autoplay: true,
                            openPlayer: false,
                          );
                        },
                        borderRadius: AppRadii.all(AppRadii.md),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.sm,
                          ),
                          decoration: BoxDecoration(
                            color: isCurrent
                                ? scheme.primary.withValues(alpha: 0.12)
                                : Colors.transparent,
                            borderRadius: AppRadii.all(AppRadii.md),
                          ),
                          child: Row(
                            children: [
                              Stack(
                                alignment: Alignment.center,
                                children: [
                                  SizedBox(
                                    width: 48,
                                    height: 48,
                                    child: TrackArtwork(
                                      track: track,
                                      borderRadius: AppRadii.all(AppRadii.sm),
                                    ),
                                  ),
                                  if (isPlaying)
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: Colors.black45,
                                        borderRadius: AppRadii.all(AppRadii.sm),
                                      ),
                                      child: Center(
                                        child: PhosphorIcon(
                                          PhosphorIcons.speakerHigh(
                                            PhosphorIconsStyle.fill,
                                          ),
                                          size: 20,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                ],
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
                                        fontWeight: isCurrent
                                            ? FontWeight.bold
                                            : AppType.body,
                                        color: isCurrent
                                            ? scheme.primary
                                            : scheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${track.artist} · ${_formatDuration(track.duration)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: textTheme.bodySmall?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: PhosphorIcon(AppIcons.more, size: 20),
                                color: scheme.onSurfaceVariant,
                                onPressed: () => _openMenu(track, controller),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                  childCount: tracks.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
