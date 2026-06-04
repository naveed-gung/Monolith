import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../core/models/music_models.dart';
import '../../../core/services/lyrics_service.dart';

/// Bottom sheet showing a track's lyrics. Synced (`.lrc` with timestamps)
/// lyrics highlight the current line off [position]; plain lyrics scroll.
class LyricsSheet extends StatelessWidget {
  const LyricsSheet({
    super.key,
    required this.track,
    required this.position,
    this.service = const LyricsService(),
  });

  final Track track;
  final ValueListenable<Duration> position;
  final LyricsService service;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final path = track.filePath;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenInset),
          child: FutureBuilder<List<LyricLine>?>(
            future: path == null ? Future.value(null) : service.loadForAudio(path),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.xxl),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              final lines = snapshot.data;
              if (lines == null || lines.isEmpty) {
                return _Empty(scrollController: scrollController);
              }
              final synced = lines.any((l) => l.time != null);
              return CustomScrollView(
                controller: scrollController,
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(
                        top: AppSpacing.lg,
                        bottom: AppSpacing.md,
                      ),
                      child: Text(
                        'Lyrics',
                        style: textTheme.titleLarge?.copyWith(
                          fontWeight: AppType.title,
                        ),
                      ),
                    ),
                  ),
                  if (!synced)
                    SliverList.list(
                      children: [
                        for (final line in lines)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text(
                              line.text.isEmpty ? ' ' : line.text,
                              style: textTheme.bodyLarge,
                            ),
                          ),
                        const SizedBox(height: AppSpacing.xxl),
                      ],
                    )
                  else
                    SliverToBoxAdapter(
                      child: ValueListenableBuilder<Duration>(
                        valueListenable: position,
                        builder: (context, pos, _) {
                          var activeIndex = -1;
                          for (var i = 0; i < lines.length; i++) {
                            final t = lines[i].time;
                            if (t != null && t <= pos) {
                              activeIndex = i;
                            } else if (t != null && t > pos) {
                              break;
                            }
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (var i = 0; i < lines.length; i++)
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 7),
                                  child: Text(
                                    lines[i].text.isEmpty ? ' ' : lines[i].text,
                                    style: textTheme.titleMedium?.copyWith(
                                      color: i == activeIndex
                                          ? scheme.primary
                                          : scheme.onSurfaceVariant
                                              .withValues(alpha: 0.6),
                                      fontWeight: i == activeIndex
                                          ? AppType.title
                                          : AppType.body,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: AppSpacing.xxl),
                            ],
                          );
                        },
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.scrollController});
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      controller: scrollController,
      children: [
        const SizedBox(height: AppSpacing.xxxl),
        Icon(Icons.lyrics_outlined, size: 40, color: scheme.onSurfaceVariant),
        const SizedBox(height: AppSpacing.md),
        Text(
          'No lyrics found',
          textAlign: TextAlign.center,
          style: textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Drop a matching “.lrc” file next to the track in the Monolith folder '
          'for synced lyrics.',
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
