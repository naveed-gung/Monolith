import 'package:flutter/material.dart';

import '../../../app/state/app_controller.dart';
import '../../../app/state/app_scope.dart';
import '../../../core/models/music_models.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/track_artwork.dart';

enum _DownloadsLibraryFilter { all, downloaded, imported }

enum _DownloadsSortOrder { titleAsc, titleDesc }

String _formatDurationLabel(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

String _formatEtaLabel(Duration duration) {
  if (duration.inMinutes >= 1) {
    return _formatDurationLabel(duration);
  }
  return '${duration.inSeconds}s';
}

String _formatBytesLabel(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  final precision = value >= 100
      ? 0
      : value >= 10
      ? 1
      : 2;
  return '${value.toStringAsFixed(precision)} ${units[unitIndex]}';
}

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  late final TextEditingController _urlController;
  late final TextEditingController _nameController;
  late final TextEditingController _downloadsFilterController;

  DownloadPreview? _preview;
  bool _loadingPreview = false;
  bool _submitting = false;
  String? _errorMessage;
  _DownloadsLibraryFilter _downloadsFilter = _DownloadsLibraryFilter.all;
  _DownloadsSortOrder _sortOrder = _DownloadsSortOrder.titleAsc;

  bool get _hasUrl => _urlController.text.trim().isNotEmpty;

  bool get _hasCustomName => _nameController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController();
    _nameController = TextEditingController();
    _downloadsFilterController = TextEditingController();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    _downloadsFilterController.dispose();
    super.dispose();
  }

  List<Track> _visibleOfflineTracks(MonolithController controller) {
    final query = _downloadsFilterController.text.trim().toLowerCase();
    final filtered = controller.offlineTracks
        .where((track) {
          final matchesSource = switch (_downloadsFilter) {
            _DownloadsLibraryFilter.all => true,
            _DownloadsLibraryFilter.downloaded =>
              track.source == TrackSource.downloaded,
            _DownloadsLibraryFilter.imported =>
              track.source == TrackSource.imported,
          };

          if (!matchesSource) {
            return false;
          }

          if (query.isEmpty) {
            return true;
          }

          final haystack = '${track.title} ${track.artist} ${track.album}'
              .toLowerCase();
          return haystack.contains(query);
        })
        .toList(growable: false);

    int compareTracks(Track left, Track right) {
      final titleCompare = left.title.toLowerCase().compareTo(
        right.title.toLowerCase(),
      );
      if (titleCompare != 0) {
        return _sortOrder == _DownloadsSortOrder.titleAsc
            ? titleCompare
            : -titleCompare;
      }

      final artistCompare = left.artist.toLowerCase().compareTo(
        right.artist.toLowerCase(),
      );
      return _sortOrder == _DownloadsSortOrder.titleAsc
          ? artistCompare
          : -artistCompare;
    }

    filtered.sort(compareTracks);
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final offlineTracks = _visibleOfflineTracks(controller);

    final content = ListView(
      padding: EdgeInsets.fromLTRB(20, widget.embedded ? 20 : 12, 20, 28),
      children: [
        SectionHeader(
          title: 'Your downloads',
          actionLabel: '${offlineTracks.length} saved',
        ),
        const SizedBox(height: 12),
        GlassPanel(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const Key('downloads-filter-field'),
                controller: _downloadsFilterController,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Filter downloads',
                  hintText: 'Title, artist, or album',
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ChoiceChip(
                    key: const Key('downloads-filter-all'),
                    label: const Text('All'),
                    selected: _downloadsFilter == _DownloadsLibraryFilter.all,
                    showCheckmark: false,
                    onSelected: (_) {
                      setState(() {
                        _downloadsFilter = _DownloadsLibraryFilter.all;
                      });
                    },
                  ),
                  ChoiceChip(
                    key: const Key('downloads-filter-downloaded'),
                    label: const Text('Downloaded'),
                    selected:
                        _downloadsFilter == _DownloadsLibraryFilter.downloaded,
                    showCheckmark: false,
                    onSelected: (_) {
                      setState(() {
                        _downloadsFilter = _DownloadsLibraryFilter.downloaded;
                      });
                    },
                  ),
                  ChoiceChip(
                    key: const Key('downloads-filter-imported'),
                    label: const Text('Imported'),
                    selected:
                        _downloadsFilter == _DownloadsLibraryFilter.imported,
                    showCheckmark: false,
                    onSelected: (_) {
                      setState(() {
                        _downloadsFilter = _DownloadsLibraryFilter.imported;
                      });
                    },
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 170),
                    child: DropdownButtonFormField<_DownloadsSortOrder>(
                      key: const Key('downloads-sort-field'),
                      initialValue: _sortOrder,
                      decoration: const InputDecoration(labelText: 'Sort'),
                      items: const [
                        DropdownMenuItem(
                          value: _DownloadsSortOrder.titleAsc,
                          child: Text('Title A to Z'),
                        ),
                        DropdownMenuItem(
                          value: _DownloadsSortOrder.titleDesc,
                          child: Text('Title Z to A'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          _sortOrder = value;
                        });
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (offlineTracks.isEmpty)
          GlassPanel(
            padding: const EdgeInsets.all(18),
            child: Text(
              controller.offlineTracks.isEmpty
                  ? 'No saved downloads yet. Start one below and it will show up here.'
                  : 'No downloads match the current filter.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          )
        else
          for (final track in offlineTracks) ...[
            _OfflineTrackTile(track: track),
            const SizedBox(height: 12),
          ],
        const SizedBox(height: 24),
        GlassPanel(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Audio downloader',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                controller.downloaderError ??
                    'Paste a supported link, inspect the metadata, edit the filename, then download audio with cover art.',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _urlController,
                keyboardType: TextInputType.url,
                onChanged: _handleUrlChanged,
                decoration: const InputDecoration(
                  labelText: 'Media link',
                  hintText: 'https://www.youtube.com/watch?v=...',
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed:
                    !_hasUrl ||
                        _loadingPreview ||
                        controller.downloaderError != null
                    ? null
                    : () => _inspectLink(controller),
                icon: _loadingPreview
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome_rounded),
                label: Text(_loadingPreview ? 'Inspecting…' : 'Inspect link'),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: scheme.error),
                ),
              ],
            ],
          ),
        ),
        if (_preview != null) ...[
          const SizedBox(height: 18),
          GlassPanel(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: SectionHeader(title: 'Detected details'),
                    ),
                    IconButton(
                      onPressed: _clearPreview,
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Clear detected details',
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _PreviewTile(preview: _preview!),
                const SizedBox(height: 16),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'File name',
                    hintText: 'Edit the output name before downloading',
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _submitting || !_hasUrl || !_hasCustomName
                      ? null
                      : () => _startDownload(controller),
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_rounded),
                  label: Text(_submitting ? 'Starting…' : 'Download audio'),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        SectionHeader(
          title: 'Download activity',
          actionLabel: controller.downloadTasks.isEmpty
              ? null
              : '${controller.downloadTasks.length} jobs',
        ),
        const SizedBox(height: 12),
        if (controller.downloadTasks.isEmpty)
          GlassPanel(
            padding: const EdgeInsets.all(18),
            child: Text(
              'No download jobs yet.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          )
        else
          for (final task in controller.downloadTasks) ...[
            _DownloadTaskTile(
              task: task,
              onPause: task.canPause
                  ? () => controller.pauseDownload(task.processId)
                  : null,
              onResume: task.canResume
                  ? () => controller.resumeDownload(task.processId)
                  : null,
              onRetry: task.canRetry
                  ? () => controller.retryDownload(task.processId)
                  : null,
              onCancel: task.isActive || task.canPause
                  ? () => controller.cancelDownload(task.processId)
                  : null,
            ),
            const SizedBox(height: 12),
          ],
      ],
    );

    if (widget.embedded) {
      return content;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Downloads')),
      body: content,
    );
  }

  Future<void> _inspectLink(MonolithController controller) async {
    setState(() {
      _loadingPreview = true;
      _errorMessage = null;
    });

    try {
      final preview = await controller.inspectDownload(_urlController.text);
      setState(() {
        _preview = preview;
        _nameController.text = preview.suggestedFileName;
      });
    } catch (error) {
      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingPreview = false;
        });
      }
    }
  }

  Future<void> _startDownload(MonolithController controller) async {
    if (_preview == null) {
      return;
    }

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      await controller.startAudioDownload(
        preview: _preview!,
        fileName: _nameController.text,
      );
    } catch (error) {
      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  void _clearPreview() {
    setState(() {
      _preview = null;
      _errorMessage = null;
      _nameController.clear();
    });
  }

  void _handleUrlChanged(String value) {
    final normalized = value.trim();
    final matchesCurrentPreview =
        _preview != null && _preview!.url == normalized;

    setState(() {
      _errorMessage = null;
      if (!matchesCurrentPreview) {
        _preview = null;
        _nameController.clear();
      }
    });
  }
}

class _OfflineTrackTile extends StatelessWidget {
  const _OfflineTrackTile({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.read(context);
    final scheme = Theme.of(context).colorScheme;
    final sourceLabel = track.source == TrackSource.imported
        ? 'Imported'
        : 'Downloaded';

    return GlassPanel(
      key: Key('downloaded-track-${track.id}'),
      padding: const EdgeInsets.all(12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => controller.selectTrack(track, openPlayer: true),
          borderRadius: BorderRadius.circular(20),
          child: Row(
            children: [
              SizedBox(
                width: 58,
                height: 58,
                child: TrackArtwork(
                  track: track,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _DetailChip(label: 'Source', value: sourceLabel),
                        _DetailChip(label: 'Album', value: track.album),
                      ],
                    ),
                  ],
                ),
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

class _PreviewTile extends StatelessWidget {
  const _PreviewTile({required this.preview});

  final DownloadPreview preview;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: 72,
            height: 72,
            child: preview.thumbnailUrl == null
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh,
                    ),
                    child: Icon(
                      Icons.music_note_rounded,
                      color: scheme.primary,
                    ),
                  )
                : Image.network(
                    preview.thumbnailUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHigh,
                      ),
                      child: Icon(
                        Icons.music_note_rounded,
                        color: scheme.primary,
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                preview.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                preview.uploader ?? 'Unknown uploader',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (preview.duration != null) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _DetailChip(
                      label: 'Time',
                      value: _formatDurationLabel(preview.duration!),
                    ),
                    if (preview.estimatedSizeBytes != null)
                      _DetailChip(
                        label: 'Size',
                        value: _formatBytesLabel(preview.estimatedSizeBytes!),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DownloadTaskTile extends StatelessWidget {
  const _DownloadTaskTile({
    required this.task,
    this.onPause,
    this.onResume,
    this.onRetry,
    this.onCancel,
  });

  final DownloadTaskInfo task;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onRetry;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return GlassPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      task.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: 2,
                children: [
                  if (onPause != null)
                    _TaskActionButton(
                      onPressed: onPause!,
                      icon: Icons.pause_rounded,
                      tooltip: 'Pause download',
                    ),
                  if (onResume != null)
                    _TaskActionButton(
                      onPressed: onResume!,
                      icon: Icons.play_arrow_rounded,
                      tooltip: 'Resume download',
                    ),
                  if (onRetry != null)
                    _TaskActionButton(
                      onPressed: onRetry!,
                      icon: Icons.refresh_rounded,
                      tooltip: 'Retry download',
                    ),
                  if (onCancel != null)
                    _TaskActionButton(
                      onPressed: onCancel!,
                      icon: Icons.close_rounded,
                      tooltip: 'Cancel download',
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: task.status == DownloadTaskStatus.completed
                ? 1
                : task.status == DownloadTaskStatus.paused
                ? task.progress
                : task.progress == 0
                ? null
                : task.progress,
          ),
          const SizedBox(height: 8),
          Text(
            task.statusLabel,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: _statusColor(context, task.status),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (task.mediaDuration != null)
                _DetailChip(
                  label: 'Time',
                  value: _formatDurationLabel(task.mediaDuration!),
                ),
              if (task.totalBytes != null)
                _DetailChip(
                  label: 'Size',
                  value: _formatBytesLabel(task.totalBytes!),
                ),
              if (task.downloadedBytes != null &&
                  (task.status == DownloadTaskStatus.downloading ||
                      task.status == DownloadTaskStatus.paused))
                _DetailChip(
                  label: 'Done',
                  value: _formatBytesLabel(task.downloadedBytes!),
                ),
              if (task.downloadSpeedBytesPerSecond != null &&
                  task.status == DownloadTaskStatus.downloading)
                _DetailChip(
                  label: 'Speed',
                  value:
                      '${_formatBytesLabel(task.downloadSpeedBytesPerSecond!)}/s',
                ),
              if (task.eta > Duration.zero)
                _DetailChip(label: 'ETA', value: _formatEtaLabel(task.eta)),
            ],
          ),
          if (task.errorMessage != null) ...[
            const SizedBox(height: 6),
            Text(
              task.errorMessage!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ],
          if (task.latestDetailLine != null &&
              (task.status == DownloadTaskStatus.paused ||
                  task.status == DownloadTaskStatus.cancelled ||
                  task.status == DownloadTaskStatus.failed)) ...[
            const SizedBox(height: 8),
            DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Text(
                  task.latestDetailLine!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static Color _statusColor(BuildContext context, DownloadTaskStatus status) {
    final scheme = Theme.of(context).colorScheme;
    switch (status) {
      case DownloadTaskStatus.completed:
        return scheme.primary;
      case DownloadTaskStatus.paused:
        return scheme.tertiary;
      case DownloadTaskStatus.failed:
        return scheme.error;
      case DownloadTaskStatus.cancelled:
        return scheme.onSurfaceVariant;
      case DownloadTaskStatus.ready:
      case DownloadTaskStatus.downloading:
        return scheme.primary;
    }
  }
}

class _DetailChip extends StatelessWidget {
  const _DetailChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          '$label $value',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ),
    );
  }
}

class _TaskActionButton extends StatelessWidget {
  const _TaskActionButton({
    required this.onPressed,
    required this.icon,
    required this.tooltip,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      tooltip: tooltip,
    );
  }
}
