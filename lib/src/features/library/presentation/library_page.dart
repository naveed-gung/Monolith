import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/state/app_controller.dart';
import '../../../app/state/app_scope.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../core/models/music_models.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/track_artwork.dart';

enum _TrackAction { edit, delete, addToPlaylist, share }

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key, this.onOpenSettings});

  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    void showMsg(String msg) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(msg)));
    }

    Future<void> editTrack(Track track) async {
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
              TextField(controller: titleC, decoration: const InputDecoration(labelText: 'Title'), textCapitalization: TextCapitalization.words),
              const SizedBox(height: AppSpacing.md),
              TextField(controller: artistC, decoration: const InputDecoration(labelText: 'Artist'), textCapitalization: TextCapitalization.words),
              const SizedBox(height: AppSpacing.md),
              TextField(controller: albumC, decoration: const InputDecoration(labelText: 'Album'), textCapitalization: TextCapitalization.words),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      );
      final t = titleC.text; final a = artistC.text; final al = albumC.text;
      titleC.dispose(); artistC.dispose(); albumC.dispose();
      if (save != true || !context.mounted) return;
      showMsg(await controller.renameTrackMetadata(track: track, title: t, artist: a, album: al));
    }

    Future<void> deleteTrack(Track track) async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Remove track'),
          content: Text('Remove ${track.title} from your library?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
          ],
        ),
      );
      if (ok != true || !context.mounted) return;
      showMsg(await controller.deleteTrack(track));
    }

    Future<void> addToPlaylist(Track track) async {
      final playlistC = TextEditingController();
      final name = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.screenInset, AppSpacing.sm, AppSpacing.screenInset, AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add to playlist', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.md),
              if (controller.playlistNames.isNotEmpty)
                Wrap(
                  spacing: AppSpacing.sm, runSpacing: AppSpacing.sm,
                  children: [
                    for (final n in controller.playlistNames)
                      ActionChip(label: Text(n), onPressed: () => Navigator.pop(ctx, n)),
                  ],
                ),
              const SizedBox(height: AppSpacing.md),
              TextField(controller: playlistC, decoration: const InputDecoration(labelText: 'New playlist name', hintText: 'Night drive mix'), textCapitalization: TextCapitalization.words),
              const SizedBox(height: AppSpacing.lg),
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel'))),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: FilledButton.icon(onPressed: () => Navigator.pop(ctx, playlistC.text.trim()), icon: PhosphorIcon(AppIcons.plusCircle, size: 18), label: const Text('Create & add'))),
              ]),
            ],
          ),
        ),
      );
      playlistC.dispose();
      if (name == null || name.isEmpty || !context.mounted) return;
      showMsg(controller.addTrackToPlaylist(track: track, playlistName: name));
    }

    Future<void> shareTrack(Track track) async {
      try {
        final fp = track.filePath;
        if (fp != null && fp.trim().isNotEmpty) {
          await Share.shareXFiles([XFile(fp)], text: '${track.title} • ${track.artist}');
        } else {
          await Share.share('${track.title} • ${track.artist}');
        }
      } catch (e) {
        if (context.mounted) showMsg('Sharing failed: $e');
      }
    }

    Future<void> openMenu(Track track) async {
      final action = await showModalBottomSheet<_TrackAction>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(leading: PhosphorIcon(AppIcons.edit), title: const Text('Edit details'), onTap: () => Navigator.pop(ctx, _TrackAction.edit)),
              ListTile(leading: PhosphorIcon(AppIcons.addToPlaylist), title: const Text('Add to playlist'), onTap: () => Navigator.pop(ctx, _TrackAction.addToPlaylist)),
              ListTile(leading: PhosphorIcon(AppIcons.share), title: const Text('Share'), onTap: () => Navigator.pop(ctx, _TrackAction.share)),
              ListTile(leading: PhosphorIcon(AppIcons.delete), title: const Text('Delete'), onTap: () => Navigator.pop(ctx, _TrackAction.delete)),
            ],
          ),
        ),
      );
      switch (action) {
        case _TrackAction.edit: await editTrack(track);
        case _TrackAction.delete: await deleteTrack(track);
        case _TrackAction.addToPlaylist: await addToPlaylist(track);
        case _TrackAction.share: await shareTrack(track);
        case null: return;
      }
    }

    return CustomScrollView(
      slivers: [
        // ── Large header ──────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenInset,
              AppSpacing.xl,
              AppSpacing.screenInset,
              0,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Library',
                        style: textTheme.displaySmall?.copyWith(
                          fontWeight: AppType.display,
                          letterSpacing: AppType.trackTight,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        controller.isLibraryLoading
                            ? 'Loading…'
                            : '${controller.tracks.length} tracks',
                        style: textTheme.bodyLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onOpenSettings,
                  icon: PhosphorIcon(AppIcons.settings, size: 22),
                  color: scheme.onSurfaceVariant,
                  tooltip: 'Settings',
                ),
              ],
            ),
          ),
        ),

        // ── Now playing hero ──────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenInset,
              AppSpacing.xl,
              AppSpacing.screenInset,
              0,
            ),
            child: _NowPlayingHero(controller: controller),
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
              onSelected: controller.selectLibraryCategory,
            ),
          ),
        ),

        // ── Content ───────────────────────────────────────────────────
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenInset,
            AppSpacing.xl,
            AppSpacing.screenInset,
            180,
          ),
          sliver: switch (controller.selectedCategory) {
            LibraryCategory.tracks => _TracksSilver(
                controller: controller,
                onEdit: editTrack,
                onDelete: deleteTrack,
                onPlaylist: addToPlaylist,
                onShare: shareTrack,
                onMenu: openMenu,
              ),
            LibraryCategory.artists =>
              _ArtistSliver(controller: controller),
            LibraryCategory.albums =>
              _AlbumSliver(controller: controller),
            LibraryCategory.playlists =>
              _PlaylistSliver(controller: controller),
          },
        ),
      ],
    );
  }
}

// ── Now Playing Hero ────────────────────────────────────────────────────────

class _NowPlayingHero extends StatelessWidget {
  const _NowPlayingHero({required this.controller});
  final MonolithController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final track = controller.currentTrack;
    final canPlay = track.canPlay;

    return AppCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: Stack(
        children: [
          // Artwork background (blurred)
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(
                color: scheme.primaryContainer.withValues(alpha: 0.6),
              ),
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                // Artwork
                SizedBox(
                  width: 72,
                  height: 72,
                  child: ClipRRect(
                    borderRadius: AppRadii.all(AppRadii.md),
                    child: TrackArtwork(
                      track: track,
                      borderRadius: AppRadii.all(AppRadii.md),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        canPlay ? 'Now Playing' : 'Up next',
                        style: textTheme.labelSmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: AppType.label,
                          letterSpacing: AppType.trackWide,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: AppType.title,
                        ),
                      ),
                      Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // Play button
                FilledButton(
                  onPressed: canPlay
                      ? () => controller.selectTrack(
                            track,
                            openPlayer: true,
                          )
                      : null,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    minimumSize: const Size(48, 48),
                    shape: const CircleBorder(),
                  ),
                  child: PhosphorIcon(
                    controller.isPlaying
                        ? AppIcons.pauseCircle
                        : AppIcons.playCircle,
                    size: 22,
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

// ── Category tabs ───────────────────────────────────────────────────────────

class _CategoryTabs extends StatelessWidget {
  const _CategoryTabs({required this.selected, required this.onSelected});
  final LibraryCategory selected;
  final ValueChanged<LibraryCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final labels = {
      LibraryCategory.tracks: 'Tracks',
      LibraryCategory.artists: 'Artists',
      LibraryCategory.albums: 'Albums',
      LibraryCategory.playlists: 'Playlists',
    };

    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final entry in labels.entries)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: AnimatedContainer(
                duration: AppMotion.durFast,
                curve: AppMotion.standard,
                decoration: BoxDecoration(
                  color: entry.key == selected
                      ? scheme.primary
                      : scheme.surfaceContainerLow,
                  borderRadius: AppRadii.all(AppRadii.pill),
                  border: Border.all(
                    color: entry.key == selected
                        ? Colors.transparent
                        : scheme.outlineVariant.withValues(alpha: 0.5),
                    width: 0.5,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => onSelected(entry.key),
                    borderRadius: AppRadii.all(AppRadii.pill),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.xs,
                      ),
                      child: Text(
                        entry.value,
                        style: textTheme.labelMedium?.copyWith(
                          color: entry.key == selected
                              ? scheme.onPrimary
                              : scheme.onSurfaceVariant,
                          fontWeight: entry.key == selected
                              ? AppType.label
                              : AppType.body,
                        ),
                      ),
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

// ── Tracks sliver ───────────────────────────────────────────────────────────

class _TracksSilver extends StatelessWidget {
  const _TracksSilver({
    required this.controller,
    required this.onEdit,
    required this.onDelete,
    required this.onPlaylist,
    required this.onShare,
    required this.onMenu,
  });

  final MonolithController controller;
  final Future<void> Function(Track) onEdit;
  final Future<void> Function(Track) onDelete;
  final Future<void> Function(Track) onPlaylist;
  final Future<void> Function(Track) onShare;
  final Future<void> Function(Track) onMenu;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tracks = controller.tracks;
    final highlights = controller.highlightedTracks;
    final gridRows = (highlights.length / 2).ceil();

    if (controller.isLibraryLoading) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xxxl),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    // Build as flat list: [header] + [N track rows] + [grid header] + [M grid rows]
    // Total = 1 + tracks.length + 1 + gridRows
    final totalCount = 1 + tracks.length + 1 + gridRows;

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          // 0: tracks section header
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: SectionHeader(
                title: 'Tracks',
                actionLabel: '${tracks.length} total',
              ),
            );
          }
          // 1..tracks.length: track rows
          if (index <= tracks.length) {
            final track = tracks[index - 1];
            final isLast = index == tracks.length;
            return Column(
              children: [
                _TrackRow(
                  track: track,
                  isActive: controller.currentTrack.id == track.id,
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
          // tracks.length + 1: grid section header
          if (index == tracks.length + 1) {
            return Padding(
              padding: const EdgeInsets.only(
                top: AppSpacing.xxl,
                bottom: AppSpacing.lg,
              ),
              child: SectionHeader(title: 'Recent additions'),
            );
          }
          // tracks.length + 2 .. totalCount - 1: grid rows (2 albums per row)
          final row = index - tracks.length - 2;
          final aIdx = row * 2;
          if (aIdx >= highlights.length) return const SizedBox.shrink();
          final a = highlights[aIdx];
          final b = aIdx + 1 < highlights.length ? highlights[aIdx + 1] : null;
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _AlbumCard(
                    track: a,
                    onTap: () => controller.selectTrack(a, openPlayer: true),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: b != null
                      ? _AlbumCard(
                          track: b,
                          onTap: () =>
                              controller.selectTrack(b, openPlayer: true),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          );
        },
        childCount: totalCount,
      ),
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
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm + AppSpacing.xs),
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
                      fontWeight:
                          isActive ? AppType.title : AppType.body,
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

// ── Album card ──────────────────────────────────────────────────────────────

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
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

// ── Artist sliver ───────────────────────────────────────────────────────────

class _ArtistSliver extends StatelessWidget {
  const _ArtistSliver({required this.controller});
  final MonolithController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final artists = controller.libraryArtists;

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index == 0) {
            return const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.md),
              child: SectionHeader(title: 'Artists'),
            );
          }
          final artist = artists[index - 1];
          final trackCount = controller.tracks
              .where((t) => t.artist == artist)
              .length;
          final isLast = index == artists.length;

          return Column(
            children: [
              InkWell(
                onTap: () {
                  final t = controller.tracks
                      .firstWhere((t) => t.artist == artist);
                  controller.selectTrack(t, openPlayer: true);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.md,
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: scheme.primaryContainer,
                        child: Text(
                          artist.substring(0, 1).toUpperCase(),
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
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
                            Text(artist, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: AppType.body)),
                            Text('$trackCount tracks', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      PhosphorIcon(AppIcons.caretRight, size: 18, color: scheme.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
              if (!isLast)
                Divider(height: 1, indent: 60, color: scheme.outlineVariant.withValues(alpha: 0.35)),
            ],
          );
        },
        childCount: artists.length + 1,
      ),
    );
  }
}

// ── Albums sliver ───────────────────────────────────────────────────────────

class _AlbumSliver extends StatelessWidget {
  const _AlbumSliver({required this.controller});
  final MonolithController controller;

  @override
  Widget build(BuildContext context) {
    final highlights = controller.albumHighlights;
    final rows = (highlights.length / 2).ceil();

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index == 0) {
            return const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.lg),
              child: SectionHeader(title: 'Albums'),
            );
          }
          final row = index - 1;
          if (row >= rows) return null;
          final a = highlights[row * 2];
          final b = row * 2 + 1 < highlights.length
              ? highlights[row * 2 + 1]
              : null;
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _AlbumCard(track: a, onTap: () => controller.selectTrack(a, openPlayer: true))),
                if (b != null) ...[
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: _AlbumCard(track: b, onTap: () => controller.selectTrack(b, openPlayer: true))),
                ] else
                  const Expanded(child: SizedBox()),
              ],
            ),
          );
        },
        childCount: rows + 1,
      ),
    );
  }
}

// ── Playlists sliver ─────────────────────────────────────────────────────────

class _PlaylistSliver extends StatelessWidget {
  const _PlaylistSliver({required this.controller});
  final MonolithController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final playlists = controller.playlistNames;

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index == 0) {
            return const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.md),
              child: SectionHeader(title: 'Playlists'),
            );
          }
          final name = playlists[index - 1];
          final tracks = controller.tracksForPlaylist(name);
          final lead = controller.leadTrackForPlaylist(name);
          final isLast = index == playlists.length;

          return Column(
            children: [
              InkWell(
                onTap: lead == null ? null : () => controller.selectTrack(lead, openPlayer: true),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 56,
                        height: 56,
                        child: lead == null
                            ? Container(
                                decoration: BoxDecoration(
                                  color: scheme.primaryContainer,
                                  borderRadius: AppRadii.all(AppRadii.md),
                                ),
                                child: PhosphorIcon(AppIcons.queue, color: scheme.onPrimaryContainer),
                              )
                            : TrackArtwork(track: lead, borderRadius: AppRadii.all(AppRadii.md)),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: AppType.body)),
                            Text(tracks.isEmpty ? 'Empty' : '${tracks.length} tracks', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      PhosphorIcon(AppIcons.caretRight, size: 18, color: scheme.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
              if (!isLast) Divider(height: 1, indent: 72, color: scheme.outlineVariant.withValues(alpha: 0.35)),
            ],
          );
        },
        childCount: playlists.length + 1,
      ),
    );
  }
}
