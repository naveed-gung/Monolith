import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app/state/app_scope.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../core/models/music_models.dart';
import '../../../core/widgets/app_icons.dart';
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
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenInset,
        0,
        AppSpacing.screenInset,
        AppSpacing.xxxl,
      ),
      children: [
        GlassPanel(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Search library', style: textTheme.headlineMedium),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Search imported device songs and downloaded audio files.',
                style: textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                key: const Key('search-field'),
                controller: _queryController,
                onChanged: controller.setSearchQuery,
                decoration: InputDecoration(
                  hintText: 'Artists, songs, albums',
                  prefixIcon: PhosphorIcon(
                    AppIcons.navSearch(false),
                    size: 20,
                  ),
                  suffixIcon: controller.hasSearchFilters
                      ? IconButton(
                          onPressed: () {
                            controller.clearSearchFilters();
                            _queryController.clear();
                          },
                          icon: PhosphorIcon(AppIcons.close, size: 20),
                          tooltip: 'Clear search',
                        )
                      : null,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        if (!controller.hasSearchFilters) ...[
          SectionHeader(
            title: 'Recent library',
            actionLabel: '${controller.tracks.length} items',
          ),
          const SizedBox(height: AppSpacing.md),
          for (final track in controller.tracks.take(6)) ...[
            _SearchResultTile(track: track),
            const SizedBox(height: AppSpacing.md),
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
          const SizedBox(height: AppSpacing.md),
          if (results.isEmpty)
            GlassPanel(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Text(
                'No matches yet. Try a broader artist, song, or album term.',
                style: textTheme.bodyLarge,
              ),
            )
          else
            for (final track in results) ...[
              _SearchResultTile(track: track),
              const SizedBox(height: AppSpacing.md),
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
      borderRadius: AppRadii.all(AppRadii.md),
      child: InkWell(
        key: Key('search-track-${track.id}'),
        onTap: () => controller.selectTrack(track, openPlayer: true),
        borderRadius: AppRadii.all(AppRadii.md),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              SizedBox(
                width: 68,
                height: 68,
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
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${track.artist} • ${track.album}',
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: AppSpacing.xs + 2),
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
                icon: PhosphorIcon(AppIcons.playCircle, size: 28),
                tooltip: 'Play now',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
