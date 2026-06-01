import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app/state/app_controller.dart';
import '../../../app/state/app_scope.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../core/models/music_models.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/track_artwork.dart';

// ── Formatters ─────────────────────────────────────────────────────────────

String _fmtDuration(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

String _fmtEta(Duration d) =>
    d.inMinutes >= 1 ? _fmtDuration(d) : '${d.inSeconds}s';

String _fmtBytes(int b) {
  const u = ['B', 'KB', 'MB', 'GB'];
  var v = b.toDouble();
  var i = 0;
  while (v >= 1024 && i < u.length - 1) {
    v /= 1024;
    i++;
  }
  final p = v >= 100 ? 0 : v >= 10 ? 1 : 2;
  return '${v.toStringAsFixed(p)} ${u[i]}';
}

// ── Page ────────────────────────────────────────────────────────────────────

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key, this.embedded = false});
  final bool embedded;

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  final _urlC = TextEditingController();
  final _nameC = TextEditingController();
  final _filterC = TextEditingController();

  DownloadPreview? _preview;
  bool _inspecting = false;
  bool _submitting = false;
  String? _error;
  bool _showAdder = false;

  @override
  void dispose() {
    _urlC.dispose();
    _nameC.dispose();
    _filterC.dispose();
    super.dispose();
  }

  List<Track> _filtered(MonolithController controller) {
    final q = _filterC.text.trim().toLowerCase();
    if (q.isEmpty) return controller.offlineTracks;
    return controller.offlineTracks.where((t) {
      return '${t.title} ${t.artist} ${t.album}'.toLowerCase().contains(q);
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final filtered = _filtered(controller);
    final activeTasks = controller.downloadTasks
        .where((t) => t.isActive || t.status == DownloadTaskStatus.paused)
        .toList();
    final recentTasks = controller.downloadTasks
        .where((t) => !t.isActive && t.status != DownloadTaskStatus.paused)
        .take(5)
        .toList();

    final body = CustomScrollView(
      slivers: [
        // ── Header ────────────────────────────────────────────────────
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
                        'Downloads',
                        style: textTheme.displaySmall?.copyWith(
                          fontWeight: AppType.display,
                          letterSpacing: AppType.trackTight,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '${controller.offlineTracks.length} saved offline',
                        style: textTheme.bodyLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // Add new download button
                FilledButton.icon(
                  onPressed: () => setState(() => _showAdder = !_showAdder),
                  icon: PhosphorIcon(
                    _showAdder ? AppIcons.close : AppIcons.add,
                    size: 18,
                  ),
                  label: Text(_showAdder ? 'Cancel' : 'Add'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Adder panel (inline, not a sheet) ─────────────────────────
        if (_showAdder)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenInset,
                AppSpacing.lg,
                AppSpacing.screenInset,
                0,
              ),
              child: _AdderCard(
                urlController: _urlC,
                nameController: _nameC,
                preview: _preview,
                inspecting: _inspecting,
                submitting: _submitting,
                error: _error,
                downloaderError: controller.downloaderError,
                onInspect: () => _inspect(controller),
                onDownload: () => _download(controller),
                onClearPreview: _clearPreview,
                onUrlChanged: _onUrlChanged,
              ),
            ),
          ),

        // ── Active jobs ────────────────────────────────────────────────
        if (activeTasks.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenInset,
                AppSpacing.xxl,
                AppSpacing.screenInset,
                AppSpacing.md,
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(right: AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Text(
                    'Active',
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: AppType.label,
                      letterSpacing: AppType.trackSnug,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenInset,
            ),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: _ActiveTaskCard(
                    task: activeTasks[i],
                    onPause: activeTasks[i].canPause
                        ? () => controller
                            .pauseDownload(activeTasks[i].processId)
                        : null,
                    onResume: activeTasks[i].canResume
                        ? () => controller
                            .resumeDownload(activeTasks[i].processId)
                        : null,
                    onCancel: () =>
                        controller.cancelDownload(activeTasks[i].processId),
                  ),
                ),
                childCount: activeTasks.length,
              ),
            ),
          ),
        ],

        // ── Offline library ────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenInset,
              AppSpacing.xxl,
              AppSpacing.screenInset,
              AppSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Saved offline',
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: AppType.label,
                      letterSpacing: AppType.trackSnug,
                    ),
                  ),
                ),
                // Inline filter
                SizedBox(
                  width: 160,
                  height: 34,
                  child: TextField(
                    controller: _filterC,
                    onChanged: (_) => setState(() {}),
                    style: textTheme.bodySmall,
                    decoration: InputDecoration(
                      hintText: 'Filter…',
                      hintStyle: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      prefixIcon: PhosphorIcon(
                        AppIcons.navSearch(false),
                        size: 14,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 0,
                        horizontal: AppSpacing.sm,
                      ),
                      isDense: true,
                      filled: true,
                      fillColor: scheme.surfaceContainerLow,
                      border: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: scheme.outlineVariant.withValues(alpha: 0.4),
                          width: 0.5,
                        ),
                        borderRadius: AppRadii.all(AppRadii.pill),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: scheme.outlineVariant.withValues(alpha: 0.4),
                          width: 0.5,
                        ),
                        borderRadius: AppRadii.all(AppRadii.pill),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: scheme.primary),
                        borderRadius: AppRadii.all(AppRadii.pill),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        if (filtered.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenInset,
                vertical: AppSpacing.xxxl,
              ),
              child: Column(
                children: [
                  PhosphorIcon(
                    AppIcons.downloadFill,
                    size: 40,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    controller.offlineTracks.isEmpty
                        ? 'Nothing saved yet'
                        : 'No matches',
                    style: textTheme.titleMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    controller.offlineTracks.isEmpty
                        ? 'Tap Add to download audio from any supported URL'
                        : 'Try a different search term',
                    style: textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenInset,
            ),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final track = filtered[i];
                  final isLast = i == filtered.length - 1;
                  return Column(
                    children: [
                      _OfflineTrackRow(
                        track: track,
                        onTap: () =>
                            controller.selectTrack(track, openPlayer: true),
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
                childCount: filtered.length,
              ),
            ),
          ),

        // ── Recent completed ────────────────────────────────────────────
        if (recentTasks.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenInset,
                AppSpacing.xxl,
                AppSpacing.screenInset,
                AppSpacing.md,
              ),
              child: Text(
                'Recent activity',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: AppType.label,
                  letterSpacing: AppType.trackSnug,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenInset,
              0,
              AppSpacing.screenInset,
              0,
            ),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final task = recentTasks[i];
                  return _RecentTaskRow(
                    task: task,
                    onRetry: task.canRetry
                        ? () => controller.retryDownload(task.processId)
                        : null,
                  );
                },
                childCount: recentTasks.length,
              ),
            ),
          ),
        ],

        const SliverToBoxAdapter(
          child: SizedBox(height: 180),
        ),
      ],
    );

    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Downloads')),
      body: body,
    );
  }

  Future<void> _inspect(MonolithController controller) async {
    setState(() {
      _inspecting = true;
      _error = null;
    });
    try {
      final p = await controller.inspectDownload(_urlC.text);
      setState(() {
        _preview = p;
        _nameC.text = p.suggestedFileName;
      });
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _inspecting = false);
    }
  }

  Future<void> _download(MonolithController controller) async {
    if (_preview == null) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await controller.startAudioDownload(
        preview: _preview!,
        fileName: _nameC.text,
      );
      setState(() => _showAdder = false);
      _clearPreview();
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _clearPreview() {
    setState(() {
      _preview = null;
      _error = null;
      _nameC.clear();
    });
  }

  void _onUrlChanged(String v) {
    final url = v.trim();
    setState(() {
      _error = null;
      if (_preview != null && _preview!.url != url) {
        _preview = null;
        _nameC.clear();
      }
    });
  }
}

// ── Adder card ──────────────────────────────────────────────────────────────

class _AdderCard extends StatelessWidget {
  const _AdderCard({
    required this.urlController,
    required this.nameController,
    required this.preview,
    required this.inspecting,
    required this.submitting,
    required this.error,
    required this.downloaderError,
    required this.onInspect,
    required this.onDownload,
    required this.onClearPreview,
    required this.onUrlChanged,
  });

  final TextEditingController urlController;
  final TextEditingController nameController;
  final DownloadPreview? preview;
  final bool inspecting;
  final bool submitting;
  final String? error;
  final String? downloaderError;
  final VoidCallback onInspect;
  final VoidCallback onDownload;
  final VoidCallback onClearPreview;
  final ValueChanged<String> onUrlChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasUrl = urlController.text.trim().isNotEmpty;
    final hasName = nameController.text.trim().isNotEmpty;

    return AppCard(
      elevated: true,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PhosphorIcon(
                AppIcons.downloadFill,
                size: 20,
                color: scheme.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Download audio',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: AppType.title,
                ),
              ),
            ],
          ),
          if (downloaderError != null) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: AppRadii.all(AppRadii.sm),
              ),
              child: Text(
                downloaderError!,
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onErrorContainer,
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: urlController,
              keyboardType: TextInputType.url,
              onChanged: onUrlChanged,
              decoration: const InputDecoration(
                labelText: 'Media URL',
                hintText: 'https://youtube.com/watch?v=…',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (preview == null)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: hasUrl && !inspecting ? onInspect : null,
                  icon: inspecting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : PhosphorIcon(AppIcons.inspect, size: 18),
                  label: Text(inspecting ? 'Inspecting…' : 'Inspect link'),
                ),
              )
            else ...[
              _PreviewRow(preview: preview!),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Save as',
                  hintText: 'filename (no extension)',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onClearPreview,
                      child: const Text('Clear'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed:
                          hasUrl && hasName && !submitting ? onDownload : null,
                      icon: submitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : PhosphorIcon(AppIcons.downloadFill, size: 18),
                      label: Text(submitting ? 'Starting…' : 'Download'),
                    ),
                  ),
                ],
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: AppRadii.all(AppRadii.sm),
                ),
                child: Text(
                  error!,
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.preview});
  final DownloadPreview preview;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        ClipRRect(
          borderRadius: AppRadii.all(AppRadii.sm),
          child: SizedBox(
            width: 56,
            height: 56,
            child: preview.thumbnailUrl == null
                ? Container(
                    color: scheme.surfaceContainerHigh,
                    child: PhosphorIcon(AppIcons.musicNote, color: scheme.primary),
                  )
                : Image.network(
                    preview.thumbnailUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      color: scheme.surfaceContainerHigh,
                      child: PhosphorIcon(AppIcons.musicNote, color: scheme.primary),
                    ),
                  ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                preview.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyMedium?.copyWith(fontWeight: AppType.label),
              ),
              Text(
                [
                  if (preview.uploader != null) preview.uploader!,
                  if (preview.duration != null) _fmtDuration(preview.duration!),
                  if (preview.estimatedSizeBytes != null)
                    _fmtBytes(preview.estimatedSizeBytes!),
                ].join(' · '),
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Active task card ────────────────────────────────────────────────────────

class _ActiveTaskCard extends StatelessWidget {
  const _ActiveTaskCard({
    required this.task,
    this.onPause,
    this.onResume,
    this.onCancel,
  });

  final DownloadTaskInfo task;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final pct = task.progress;
    final isPaused = task.status == DownloadTaskStatus.paused;

    return AppCard(
      elevated: true,
      padding: const EdgeInsets.all(AppSpacing.lg),
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
                      style: textTheme.bodyLarge?.copyWith(
                        fontWeight: AppType.body,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      task.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onPause != null)
                    _SmallAction(
                      icon: AppIcons.pause,
                      onPressed: onPause!,
                      tooltip: 'Pause',
                    ),
                  if (onResume != null)
                    _SmallAction(
                      icon: AppIcons.play,
                      onPressed: onResume!,
                      tooltip: 'Resume',
                    ),
                  if (onCancel != null)
                    _SmallAction(
                      icon: AppIcons.close,
                      onPressed: onCancel!,
                      tooltip: 'Cancel',
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: AppRadii.all(AppRadii.pill),
            child: LinearProgressIndicator(
              value: pct == 0 && !isPaused ? null : pct,
              minHeight: 5,
              backgroundColor: scheme.outlineVariant.withValues(alpha: 0.3),
              valueColor: AlwaysStoppedAnimation<Color>(
                isPaused ? scheme.onSurfaceVariant : scheme.primary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              _StatusDot(status: task.status),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  task.statusLabel,
                  style: textTheme.labelSmall?.copyWith(
                    color: _statusColor(scheme, task.status),
                    fontWeight: AppType.label,
                  ),
                ),
              ),
              if (task.totalBytes != null)
                Text(
                  '${pct > 0 ? '${(pct * 100).round()}% · ' : ''}${_fmtBytes(task.totalBytes!)}',
                  style: textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              if (task.eta > Duration.zero) ...[
                const SizedBox(width: AppSpacing.sm),
                Text(
                  _fmtEta(task.eta),
                  style: textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
          if (task.errorMessage != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              task.errorMessage!,
              style: textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ],
        ],
      ),
    );
  }

  static Color _statusColor(ColorScheme s, DownloadTaskStatus st) =>
      switch (st) {
        DownloadTaskStatus.completed => s.primary,
        DownloadTaskStatus.failed => s.error,
        DownloadTaskStatus.paused => s.onSurfaceVariant,
        DownloadTaskStatus.cancelled => s.onSurfaceVariant,
        _ => s.primary,
      };
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});
  final DownloadTaskStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (status) {
      DownloadTaskStatus.completed => scheme.primary,
      DownloadTaskStatus.failed => scheme.error,
      DownloadTaskStatus.paused || DownloadTaskStatus.cancelled =>
        scheme.onSurfaceVariant,
      _ => scheme.primary,
    };
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

// ── Recent task row ─────────────────────────────────────────────────────────

class _RecentTaskRow extends StatelessWidget {
  const _RecentTaskRow({required this.task, this.onRetry});
  final DownloadTaskInfo task;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isOk = task.status == DownloadTaskStatus.completed;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm + 2),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isOk
                  ? scheme.primaryContainer
                  : scheme.errorContainer,
              borderRadius: AppRadii.all(AppRadii.sm),
            ),
            child: Center(
              child: PhosphorIcon(
                isOk ? AppIcons.downloadFill : AppIcons.close,
                size: 18,
                color: isOk
                    ? scheme.onPrimaryContainer
                    : scheme.onErrorContainer,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(fontWeight: AppType.body),
                ),
                Text(
                  task.statusLabel,
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (onRetry != null)
            IconButton(
              onPressed: onRetry,
              icon: PhosphorIcon(AppIcons.refresh, size: 18),
              color: scheme.onSurfaceVariant,
              tooltip: 'Retry',
              padding: const EdgeInsets.all(AppSpacing.xs),
            ),
        ],
      ),
    );
  }
}

// ── Offline track row ───────────────────────────────────────────────────────

class _OfflineTrackRow extends StatelessWidget {
  const _OfflineTrackRow({required this.track, required this.onTap});
  final Track track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isImported = track.source == TrackSource.imported;

    return InkWell(
      key: Key('downloaded-track-${track.id}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm + 2),
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
                  const SizedBox(height: 2),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: isImported
                    ? scheme.secondaryContainer
                    : scheme.primaryContainer,
                borderRadius: AppRadii.all(AppRadii.pill),
              ),
              child: Text(
                isImported ? 'Imported' : 'Downloaded',
                style: textTheme.labelSmall?.copyWith(
                  color: isImported
                      ? scheme.onSecondaryContainer
                      : scheme.onPrimaryContainer,
                  fontWeight: AppType.label,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Small action button ─────────────────────────────────────────────────────

class _SmallAction extends StatelessWidget {
  const _SmallAction({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });
  final PhosphorIconData icon;
  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: PhosphorIcon(icon, size: 18),
      tooltip: tooltip,
      padding: const EdgeInsets.all(AppSpacing.xs),
      visualDensity: VisualDensity.compact,
    );
  }
}
