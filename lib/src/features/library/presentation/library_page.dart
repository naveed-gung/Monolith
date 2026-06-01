import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/state/app_controller.dart';
import '../../../app/state/app_scope.dart';
import '../../../core/models/music_models.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/track_artwork.dart';

enum _TrackLibraryAction { edit, delete, addToPlaylist, share }

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    void showMessage(String message) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }

    Future<void> handleFilesImport() async {
      try {
        final message = await controller.importAudioFiles();
        if (!context.mounted || message == null) {
          return;
        }

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      } catch (error) {
        if (!context.mounted) {
          return;
        }

        final message = error.toString().replaceFirst('Bad state: ', '');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    }

    Future<void> editTrack(Track track) async {
      final titleController = TextEditingController(text: track.title);
      final artistController = TextEditingController(text: track.artist);
      final albumController = TextEditingController(text: track.album);

      final shouldSave = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Edit details'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Title'),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: artistController,
                  decoration: const InputDecoration(labelText: 'Artist'),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: albumController,
                  decoration: const InputDecoration(labelText: 'Album'),
                  textCapitalization: TextCapitalization.words,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Save'),
              ),
            ],
          );
        },
      );

      final updatedTitle = titleController.text;
      final updatedArtist = artistController.text;
      final updatedAlbum = albumController.text;
      titleController.dispose();
      artistController.dispose();
      albumController.dispose();

      if (shouldSave != true) {
        return;
      }

      final message = await controller.renameTrackMetadata(
        track: track,
        title: updatedTitle,
        artist: updatedArtist,
        album: updatedAlbum,
      );
      if (!context.mounted) {
        return;
      }
      showMessage(message);
    }

    Future<void> deleteTrack(Track track) async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Delete track'),
            content: Text('Remove ${track.title} from your library?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Keep'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Delete'),
              ),
            ],
          );
        },
      );

      if (confirmed != true) {
        return;
      }

      final message = await controller.deleteTrack(track);
      if (!context.mounted) {
        return;
      }
      showMessage(message);
    }

    Future<void> addTrackToPlaylist(Track track) async {
      final playlistController = TextEditingController();
      final playlistName = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Add to playlist',
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  'Pick an existing playlist or create a new one for this track.',
                  style: Theme.of(sheetContext).textTheme.bodyMedium,
                ),
                if (controller.playlistNames.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final playlistName in controller.playlistNames)
                        ActionChip(
                          label: Text(playlistName),
                          onPressed: () =>
                              Navigator.of(sheetContext).pop(playlistName),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 18),
                TextField(
                  controller: playlistController,
                  decoration: const InputDecoration(
                    labelText: 'New playlist name',
                    hintText: 'Night drive mix',
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.of(
                          sheetContext,
                        ).pop(playlistController.text.trim()),
                        icon: const Icon(Icons.add_circle_outline_rounded),
                        label: const Text('Create & add'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
      playlistController.dispose();

      if (playlistName == null || playlistName.trim().isEmpty) {
        return;
      }

      final message = controller.addTrackToPlaylist(
        track: track,
        playlistName: playlistName,
      );
      if (!context.mounted) {
        return;
      }
      showMessage(message);
    }

    Future<void> shareTrack(Track track) async {
      final summary = '${track.title} • ${track.artist}';
      try {
        final filePath = track.filePath;
        if (filePath != null && filePath.trim().isNotEmpty) {
          await Share.shareXFiles([XFile(filePath)], text: summary);
        } else {
          await Share.share(summary);
        }
      } catch (error) {
        if (!context.mounted) {
          return;
        }
        showMessage('Sharing failed: $error');
      }
    }

    Future<void> openTrackMenu(Track track) async {
      final action = await showModalBottomSheet<_TrackLibraryAction>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.edit_rounded),
                  title: const Text('Edit'),
                  subtitle: const Text('Change name and other details'),
                  onTap: () =>
                      Navigator.of(sheetContext).pop(_TrackLibraryAction.edit),
                ),
                ListTile(
                  leading: const Icon(Icons.playlist_add_rounded),
                  title: const Text('Add to playlist'),
                  onTap: () => Navigator.of(
                    sheetContext,
                  ).pop(_TrackLibraryAction.addToPlaylist),
                ),
                ListTile(
                  leading: const Icon(Icons.share_rounded),
                  title: const Text('Share'),
                  onTap: () =>
                      Navigator.of(sheetContext).pop(_TrackLibraryAction.share),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: const Text('Delete'),
                  onTap: () => Navigator.of(
                    sheetContext,
                  ).pop(_TrackLibraryAction.delete),
                ),
              ],
            ),
          );
        },
      );

      switch (action) {
        case _TrackLibraryAction.edit:
          await editTrack(track);
          return;
        case _TrackLibraryAction.delete:
          await deleteTrack(track);
          return;
        case _TrackLibraryAction.addToPlaylist:
          await addTrackToPlaylist(track);
          return;
        case _TrackLibraryAction.share:
          await shareTrack(track);
          return;
        case null:
          return;
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 220),
      children: [
        GlassPanel(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Device library', style: textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                controller.isLibraryLoading
                    ? 'Scanning your device and loading downloaded audio.'
                    : controller.hasPlayableTracks
                    ? '${controller.tracks.length} tracks ready across your device, downloads, and Files imports.'
                    : 'Grant media access, then import audio from Files if tracks are still missing.',
                style: textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, constraints) {
                  final compactActions = constraints.maxWidth < 360;

                  return DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      gradient: LinearGradient(
                        colors: [
                          scheme.primaryContainer,
                          scheme.secondaryContainer,
                          scheme.tertiaryContainer,
                        ],
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            controller.currentTrack.title,
                            style: textTheme.titleLarge?.copyWith(
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${controller.currentTrack.artist} • ${controller.currentTrack.album}',
                            style: textTheme.bodyLarge?.copyWith(
                              color: scheme.onPrimaryContainer.withOpacity(
                                0.84,
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          if (compactActions)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                FilledButton.icon(
                                  key: const Key('hero-resume-button'),
                                  onPressed: controller.currentTrack.canPlay
                                      ? () => controller.selectTrack(
                                          controller.currentTrack,
                                          openPlayer: true,
                                        )
                                      : null,
                                  icon: const Icon(Icons.play_arrow_rounded),
                                  label: const Text('Open player'),
                                ),
                                const SizedBox(height: 12),
                                FilledButton.tonalIcon(
                                  key: const Key('hero-import-button'),
                                  onPressed: controller.isImportingAudio
                                      ? null
                                      : handleFilesImport,
                                  icon: controller.isImportingAudio
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.audio_file_rounded),
                                  label: Text(
                                    controller.isImportingAudio
                                        ? 'Importing audio'
                                        : 'Import from Files',
                                  ),
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  onPressed: () {
                                    controller.refreshLibrary(
                                      retryPermissionRequest: true,
                                    );
                                  },
                                  icon: const Icon(Icons.sync_rounded),
                                  label: const Text('Rescan device'),
                                ),
                              ],
                            )
                          else
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                FilledButton.icon(
                                  key: const Key('hero-resume-button'),
                                  onPressed: controller.currentTrack.canPlay
                                      ? () => controller.selectTrack(
                                          controller.currentTrack,
                                          openPlayer: true,
                                        )
                                      : null,
                                  icon: const Icon(Icons.play_arrow_rounded),
                                  label: const Text('Open player'),
                                ),
                                FilledButton.tonalIcon(
                                  key: const Key('hero-import-button'),
                                  onPressed: controller.isImportingAudio
                                      ? null
                                      : handleFilesImport,
                                  icon: controller.isImportingAudio
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.audio_file_rounded),
                                  label: Text(
                                    controller.isImportingAudio
                                        ? 'Importing audio'
                                        : 'Import from Files',
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () {
                                    controller.refreshLibrary(
                                      retryPermissionRequest: true,
                                    );
                                  },
                                  icon: const Icon(Icons.sync_rounded),
                                  label: const Text('Rescan device'),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _CategorySelector(
          selected: controller.selectedCategory,
          onSelected: controller.selectLibraryCategory,
        ),
        const SizedBox(height: 28),
        switch (controller.selectedCategory) {
          LibraryCategory.tracks => _TracksView(
            controller: controller,
            onEditTrack: editTrack,
            onDeleteTrack: deleteTrack,
            onAddToPlaylist: addTrackToPlaylist,
            onShareTrack: shareTrack,
            onOpenTrackMenu: openTrackMenu,
          ),
          LibraryCategory.artists => _ArtistsView(controller: controller),
          LibraryCategory.albums => _AlbumsView(controller: controller),
          LibraryCategory.playlists => _PlaylistsView(controller: controller),
        },
      ],
    );
  }
}

class _CategorySelector extends StatelessWidget {
  const _CategorySelector({required this.selected, required this.onSelected});

  final LibraryCategory selected;
  final ValueChanged<LibraryCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    final labels = {
      LibraryCategory.tracks: 'Tracks',
      LibraryCategory.artists: 'Artists',
      LibraryCategory.albums: 'Albums',
      LibraryCategory.playlists: 'Playlists',
    };

    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: labels.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final category = labels.keys.elementAt(index);
          final active = category == selected;
          return ChoiceChip(
            label: Text(labels[category]!),
            selected: active,
            onSelected: (_) => onSelected(category),
            showCheckmark: false,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          );
        },
      ),
    );
  }
}

class _TracksView extends StatelessWidget {
  const _TracksView({
    required this.controller,
    required this.onEditTrack,
    required this.onDeleteTrack,
    required this.onAddToPlaylist,
    required this.onShareTrack,
    required this.onOpenTrackMenu,
  });

  final MonolithController controller;
  final Future<void> Function(Track track) onEditTrack;
  final Future<void> Function(Track track) onDeleteTrack;
  final Future<void> Function(Track track) onAddToPlaylist;
  final Future<void> Function(Track track) onShareTrack;
  final Future<void> Function(Track track) onOpenTrackMenu;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Tracks',
          actionLabel: '${controller.tracks.length} total',
        ),
        const SizedBox(height: 14),
        if (controller.isLibraryLoading)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          for (final track in controller.tracks) ...[
            _TrackTile(
              track: track,
              onEdit: () => onEditTrack(track),
              onDelete: () => onDeleteTrack(track),
              onAddToPlaylist: () => onAddToPlaylist(track),
              onShare: () => onShareTrack(track),
              onShowMenu: () => onOpenTrackMenu(track),
            ),
            const SizedBox(height: 12),
          ],
        const SizedBox(height: 28),
        SectionHeader(
          title: 'Latest arrivals',
          actionLabel: 'Albums',
          onAction: () =>
              controller.selectLibraryCategory(LibraryCategory.albums),
        ),
        const SizedBox(height: 14),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: controller.highlightedTracks.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 0.76,
          ),
          itemBuilder: (context, index) {
            final track = controller.highlightedTracks[index];
            return _AlbumTile(
              track: track,
              onTap: () => controller.selectTrack(track, openPlayer: true),
              onLongPress: () => onOpenTrackMenu(track),
            );
          },
        ),
      ],
    );
  }
}

class _ArtistsView extends StatelessWidget {
  const _ArtistsView({required this.controller});

  final MonolithController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final artists = controller.libraryArtists;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Artist channels',
          actionLabel: 'Search',
          onAction: () => controller.selectTab(AppTab.search),
        ),
        const SizedBox(height: 14),
        for (final artist in artists) ...[
          GlassPanel(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: scheme.primaryContainer,
                  child: Text(
                    artist.substring(0, 1),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        artist,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${controller.tracks.where((track) => track.artist == artist).length} tracks available',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () {
                    final track = controller.tracks.firstWhere(
                      (candidate) => candidate.artist == artist,
                    );
                    controller.selectTrack(track, openPlayer: true);
                  },
                  icon: const Icon(Icons.play_circle_fill_rounded),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _AlbumsView extends StatelessWidget {
  const _AlbumsView({required this.controller});

  final MonolithController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Albums',
          actionLabel: 'Tracks',
          onAction: () =>
              controller.selectLibraryCategory(LibraryCategory.tracks),
        ),
        const SizedBox(height: 14),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: controller.albumHighlights.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 0.76,
          ),
          itemBuilder: (context, index) {
            final track = controller.albumHighlights[index];
            return _AlbumTile(
              track: track,
              onTap: () => controller.selectTrack(track, openPlayer: true),
              onLongPress: () {},
            );
          },
        ),
      ],
    );
  }
}

class _PlaylistsView extends StatelessWidget {
  const _PlaylistsView({required this.controller});

  final MonolithController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final playlists = controller.playlistNames;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Playlists',
          actionLabel: 'Tracks',
          onAction: () =>
              controller.selectLibraryCategory(LibraryCategory.tracks),
        ),
        const SizedBox(height: 14),
        for (final playlistName in playlists) ...[
          Builder(
            builder: (context) {
              final playlistTracks = controller.tracksForPlaylist(playlistName);
              final leadTrack = controller.leadTrackForPlaylist(playlistName);

              return GlassPanel(
                padding: const EdgeInsets.all(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: leadTrack == null
                      ? null
                      : () =>
                            controller.selectTrack(leadTrack, openPlayer: true),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 64,
                        height: 64,
                        child: leadTrack == null
                            ? DecoratedBox(
                                decoration: BoxDecoration(
                                  color: scheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Icon(
                                  Icons.queue_music_rounded,
                                  color: scheme.onPrimaryContainer,
                                ),
                              )
                            : TrackArtwork(
                                track: leadTrack,
                                borderRadius: BorderRadius.circular(18),
                              ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              playlistName,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              playlistTracks.isEmpty
                                  ? 'No tracks yet'
                                  : '${playlistTracks.length} tracks',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                            if (playlistTracks.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                playlistTracks
                                    .take(2)
                                    .map((track) => track.title)
                                    .join(' • '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: leadTrack == null
                            ? null
                            : () => controller.selectTrack(
                                leadTrack,
                                openPlayer: true,
                              ),
                        icon: const Icon(Icons.play_circle_fill_rounded),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.track,
    required this.onEdit,
    required this.onDelete,
    required this.onAddToPlaylist,
    required this.onShare,
    required this.onShowMenu,
  });

  final Track track;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onAddToPlaylist;
  final VoidCallback onShare;
  final VoidCallback onShowMenu;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.read(context);
    final scheme = Theme.of(context).colorScheme;

    return Slidable(
      key: ValueKey('library-track-${track.id}'),
      startActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.42,
        children: [
          _CardSlidableAction(
            onPressed: onShare,
            backgroundColor: scheme.secondaryContainer,
            foregroundColor: scheme.onSecondaryContainer,
            icon: Icons.share_rounded,
            label: 'Share',
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(22),
            ),
          ),
          _CardSlidableAction(
            onPressed: onEdit,
            backgroundColor: scheme.primaryContainer,
            foregroundColor: scheme.onPrimaryContainer,
            icon: Icons.edit_rounded,
            label: 'Edit',
          ),
        ],
      ),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.42,
        children: [
          _CardSlidableAction(
            onPressed: onAddToPlaylist,
            backgroundColor: scheme.tertiaryContainer,
            foregroundColor: scheme.onTertiaryContainer,
            icon: Icons.playlist_add_rounded,
            label: 'Playlist',
          ),
          _CardSlidableAction(
            onPressed: onDelete,
            backgroundColor: scheme.errorContainer,
            foregroundColor: scheme.onErrorContainer,
            icon: Icons.delete_outline_rounded,
            label: 'Delete',
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(22),
            ),
          ),
        ],
      ),
      child: GlassPanel(
        opacity: controller.currentTrack.id == track.id ? 0.82 : 0.68,
        padding: const EdgeInsets.all(16),
        child: InkWell(
          onTap: () => controller.selectTrack(track, openPlayer: true),
          borderRadius: BorderRadius.circular(22),
          child: Row(
            children: [
              SizedBox(
                width: 58,
                height: 58,
                child: TrackArtwork(
                  track: track,
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${track.artist} • ${track.album}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onShowMenu,
                icon: const Icon(Icons.more_horiz_rounded),
                tooltip: 'Track actions',
              ),
              IconButton(
                onPressed: track.canPlay
                    ? () => controller.selectTrack(track, openPlayer: true)
                    : null,
                icon: const Icon(Icons.play_arrow_rounded),
                tooltip: 'Play track',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardSlidableAction extends StatelessWidget {
  const _CardSlidableAction({
    required this.onPressed,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.icon,
    required this.label,
    this.borderRadius = BorderRadius.zero,
  });

  final VoidCallback onPressed;
  final Color backgroundColor;
  final Color foregroundColor;
  final IconData icon;
  final String label;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: Material(
            color: backgroundColor,
            child: InkWell(
              onTap: onPressed,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: foregroundColor),
                    const SizedBox(height: 8),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: foregroundColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AlbumTile extends StatelessWidget {
  const _AlbumTile({
    required this.track,
    required this.onTap,
    required this.onLongPress,
  });

  final Track track;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(26),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(26),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TrackArtwork(
                  track: track,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              Text(
                '${track.artist} • ${track.genre}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
