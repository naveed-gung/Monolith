import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app/state/app_scope.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../core/models/music_models.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/track_artwork.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late final TextEditingController _queryC;

  @override
  void initState() {
    super.initState();
    _queryC = TextEditingController();
  }

  @override
  void dispose() {
    _queryC.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final q = AppScope.watch(context).searchQuery;
    if (_queryC.text != q) {
      _queryC.value = TextEditingValue(
        text: q,
        selection: TextSelection.collapsed(offset: q.length),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final results = controller.searchResults;
    final hasFilter = controller.hasSearchFilters;

    return CustomScrollView(
      slivers: [
        // ── Search header ─────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenInset,
              AppSpacing.xl,
              AppSpacing.screenInset,
              AppSpacing.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Search',
                  style: textTheme.displaySmall?.copyWith(
                    fontWeight: AppType.display,
                    letterSpacing: AppType.trackTight,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                TextField(
                  key: const Key('search-field'),
                  controller: _queryC,
                  onChanged: controller.setSearchQuery,
                  style: textTheme.bodyLarge,
                  decoration: InputDecoration(
                    hintText: 'Artists, songs, albums…',
                    prefixIcon: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: PhosphorIcon(
                        AppIcons.navSearch(hasFilter),
                        size: 20,
                        color: hasFilter
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                    suffixIcon: hasFilter
                        ? IconButton(
                            onPressed: () {
                              controller.clearSearchFilters();
                              _queryC.clear();
                            },
                            icon: PhosphorIcon(AppIcons.close, size: 18),
                            tooltip: 'Clear',
                          )
                        : null,
                    filled: true,
                    fillColor: scheme.surfaceContainerLow,
                    border: OutlineInputBorder(
                      borderSide: BorderSide(
                        color:
                            scheme.outlineVariant.withValues(alpha: 0.5),
                        width: 0.5,
                      ),
                      borderRadius: AppRadii.all(AppRadii.md),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color:
                            scheme.outlineVariant.withValues(alpha: 0.5),
                        width: 0.5,
                      ),
                      borderRadius: AppRadii.all(AppRadii.md),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: scheme.primary,
                        width: 1.5,
                      ),
                      borderRadius: AppRadii.all(AppRadii.md),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.md,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Results / recent ──────────────────────────────────────────
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenInset,
            0,
            AppSpacing.screenInset,
            180,
          ),
          sliver: !hasFilter
              ? _RecentSliver(tracks: controller.tracks.take(8).toList())
              : results.isEmpty
              ? SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xxl),
                    child: Column(
                      children: [
                        PhosphorIcon(
                          AppIcons.navSearch(false),
                          size: 48,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'No results',
                          style: textTheme.titleMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Try a different search term',
                          style: textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : _ResultsSliver(tracks: results),
        ),
      ],
    );
  }
}

class _RecentSliver extends StatelessWidget {
  const _RecentSliver({required this.tracks});
  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(
                'Recent',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: AppType.title,
                  letterSpacing: AppType.trackSnug,
                ),
              ),
            );
          }
          final track = tracks[index - 1];
          final isLast = index == tracks.length;
          final controller = AppScope.read(context);
          return Column(
            children: [
              _SearchTile(
                track: track,
                onTap: () => controller.selectTrack(track, openPlayer: true),
              ),
              if (!isLast)
                Divider(
                  height: 1,
                  indent: 72,
                  color: scheme.outlineVariant.withValues(alpha: 0.35),
                ),
            ],
          );
        },
        childCount: tracks.length + 1,
      ),
    );
  }
}

class _ResultsSliver extends StatelessWidget {
  const _ResultsSliver({required this.tracks});
  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(
                '${tracks.length} result${tracks.length == 1 ? '' : 's'}',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: AppType.title,
                  letterSpacing: AppType.trackSnug,
                ),
              ),
            );
          }
          final track = tracks[index - 1];
          final isLast = index == tracks.length;
          final controller = AppScope.read(context);
          return Column(
            children: [
              _SearchTile(
                track: track,
                onTap: () => controller.selectTrack(track, openPlayer: true),
              ),
              if (!isLast)
                Divider(
                  height: 1,
                  indent: 72,
                  color: scheme.outlineVariant.withValues(alpha: 0.35),
                ),
            ],
          );
        },
        childCount: tracks.length + 1,
      ),
    );
  }
}

class _SearchTile extends StatelessWidget {
  const _SearchTile({required this.track, required this.onTap});
  final Track track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.read(context);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      key: Key('search-track-${track.id}'),
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
                    style: textTheme.bodyLarge?.copyWith(fontWeight: AppType.body),
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
              onPressed: () =>
                  controller.selectTrack(track, openPlayer: true),
              icon: PhosphorIcon(
                AppIcons.playCircle,
                size: 26,
                color: scheme.primary,
              ),
              padding: const EdgeInsets.all(AppSpacing.sm),
            ),
          ],
        ),
      ),
    );
  }
}
