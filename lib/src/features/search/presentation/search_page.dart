import 'package:flutter/material.dart';

import '../../../app/state/app_scope.dart';
import '../../../core/models/music_models.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/track_artwork.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late final TextEditingController _queryController;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController();
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = AppScope.watch(context);
    if (_queryController.text != controller.searchQuery) {
      _queryController.value = TextEditingValue(
        text: controller.searchQuery,
        selection: TextSelection.collapsed(
          offset: controller.searchQuery.length,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final results = controller.searchResults;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 132),
      children: [
        GlassPanel(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Search library', style: textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                'Search imported device songs and downloaded audio files.',
                style: textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                key: const Key('search-field'),
                controller: _queryController,
                onChanged: controller.setSearchQuery,
                decoration: InputDecoration(
                  hintText: 'Artists, songs, albums',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: controller.hasSearchFilters
                      ? IconButton(
                          onPressed: () {
                            controller.clearSearchFilters();
                            _queryController.clear();
                          },
                          icon: const Icon(Icons.close_rounded),
                          tooltip: 'Clear search',
                        )
                      : null,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        if (!controller.hasSearchFilters) ...[
          SectionHeader(
            title: 'Recent library',
            actionLabel: '${controller.tracks.length} items',
          ),
          const SizedBox(height: 14),
          for (final track in controller.tracks.take(6)) ...[
            _SearchResultTile(track: track),
            const SizedBox(height: 12),
          ],
        ] else ...[
          SectionHeader(
            title: 'Matching tracks',
            actionLabel: 'Clear',
            onAction: () {
              controller.clearSearchFilters();
              _queryController.clear();
            },
          ),
          const SizedBox(height: 14),
          if (results.isEmpty)
            GlassPanel(
              padding: const EdgeInsets.all(20),
              child: Text(
                'No matches yet. Try a broader artist, song, or album term.',
                style: textTheme.bodyLarge,
              ),
            )
          else
            for (final track in results) ...[
              _SearchResultTile(track: track),
              const SizedBox(height: 12),
            ],
        ],
      ],
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.read(context);
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        key: Key('search-track-${track.id}'),
        onTap: () => controller.selectTrack(track, openPlayer: true),
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              SizedBox(
                width: 68,
                height: 68,
                child: TrackArtwork(
                  track: track,
                  borderRadius: BorderRadius.circular(16),
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
                    const SizedBox(height: 6),
                    Text(
                      track.blurb,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: track.canPlay
                    ? () => controller.selectTrack(track, openPlayer: true)
                    : null,
                icon: const Icon(Icons.play_circle_fill_rounded),
                tooltip: 'Play now',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
