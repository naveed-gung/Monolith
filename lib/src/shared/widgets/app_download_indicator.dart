import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../app/state/app_scope.dart';
import '../../app/state/app_controller.dart';
import '../../core/models/music_models.dart';
import '../../core/services/app_update_service.dart';

/// A separate activity row: expanding the pill never takes width from a title.
/// The carrier opens a live menu; only a job's own stop button cancels that job.
class AppDownloadIndicator extends StatefulWidget {
  const AppDownloadIndicator({super.key, this.updateService});
  final AppUpdateService? updateService;
  @override
  State<AppDownloadIndicator> createState() => _AppDownloadIndicatorState();
}

class _AppDownloadIndicatorState extends State<AppDownloadIndicator> {
  final _menu = MenuController();
  Timer? _timer;
  bool _expanded = true;
  String _workKey = '';
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.watch(context);
    final service = widget.updateService ?? AppUpdateService.instance;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final jobs = _jobs(controller, service);
        if (jobs.isEmpty) return const SizedBox.shrink();
        final active = jobs.where((j) => j.active).toList();
        final key = active.map((j) => j.id).join('|');
        if (key != _workKey) {
          _workKey = key;
          _expanded = true;
          _timer?.cancel();
          if (active.isNotEmpty) {
            _timer = Timer(const Duration(seconds: 2), () {
              if (mounted) setState(() => _expanded = false);
            });
          }
        }
        final scheme = Theme.of(context).colorScheme;
        final done = active.isEmpty && jobs.every((j) => j.complete);
        final progress = active.isEmpty
            ? 1.0
            : active.any((j) => j.progress == null)
            ? null
            : active.fold<double>(0, (sum, j) => sum + j.progress!) /
                  active.length;
        final title = active.length == 1
            ? active.first.title
            : active.isNotEmpty
            ? '${active.length} activities'
            : 'Recent activity';
        final subtitle = active.length == 1
            ? active.first.detail
            : active.isNotEmpty
            ? 'Tap to view each task'
            : 'Tap for results';
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Align(
            alignment: Alignment.centerRight,
            child: MenuAnchor(
              controller: _menu,
              style: MenuStyle(
                backgroundColor: WidgetStatePropertyAll(
                  scheme.surfaceContainerHigh,
                ),
                elevation: const WidgetStatePropertyAll(8),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
              ),
              menuChildren: [
                SizedBox(
                  width: math.min(320, MediaQuery.sizeOf(context).width - 40),
                  child: ListenableBuilder(
                    listenable: Listenable.merge([controller, service]),
                    builder: (context, _) => ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * .55,
                      ),
                      child: SingleChildScrollView(
                        primary: false,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Padding(
                              padding: EdgeInsets.all(12),
                              child: Text(
                                'Activity',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                            for (final job in _jobs(controller, service))
                              _ActivityRow(job: job),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              builder: (context, menu, _) => Semantics(
                button: true,
                label: 'Show activity, ${active.length} active tasks',
                child: Tooltip(
                  message: 'Show activity',
                  child: Material(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(22),
                    child: InkWell(
                      key: const Key('activity-menu-button'),
                      borderRadius: BorderRadius.circular(22),
                      onTap: () => menu.isOpen ? menu.close() : menu.open(),
                      child: AnimatedSize(
                        alignment: Alignment.centerRight,
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutCubic,
                        child: Container(
                          width: _expanded
                              ? math.min(
                                  260,
                                  MediaQuery.sizeOf(context).width - 48,
                                )
                              : 44,
                          constraints: const BoxConstraints(minHeight: 44),
                          padding: EdgeInsets.all(_expanded ? 10 : 8),
                          child: _expanded
                              ? Row(
                                  children: [
                                    Icon(
                                      done
                                          ? Icons.check_circle_rounded
                                          : Icons.downloading_rounded,
                                      size: 22,
                                      color: done
                                          ? Colors.green
                                          : scheme.primary,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Text(
                                            subtitle,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: scheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(
                                      Icons.expand_more_rounded,
                                      size: 18,
                                    ),
                                  ],
                                )
                              : SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      CircularProgressIndicator(
                                        value: progress,
                                        strokeWidth: 2.5,
                                        color: done
                                            ? Colors.green
                                            : scheme.primary,
                                        backgroundColor: scheme.outlineVariant,
                                      ),
                                      if (done)
                                        const Icon(
                                          Icons.check_rounded,
                                          size: 18,
                                          color: Colors.green,
                                        )
                                      else if (active.length > 1)
                                        Text(
                                          '${active.length}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        )
                                      else
                                        const Icon(
                                          Icons.expand_more_rounded,
                                          size: 18,
                                        ),
                                    ],
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Activity {
  const _Activity(
    this.id,
    this.title,
    this.detail, {
    this.active = false,
    this.complete = false,
    this.progress,
    this.cancel,
  });
  final String id, title, detail;
  final bool active, complete;
  final double? progress;
  final VoidCallback? cancel;
}

List<_Activity> _jobs(
  MonolithController controller,
  AppUpdateService service,
) => [
  if (controller.isImportingAudio)
    _Activity(
      'music-import',
      'Importing Music',
      controller.importStatus ?? 'Preparing import…',
      active: true,
      progress: controller.importProgress,
      cancel: !controller.canCancelImport
          ? null
          : () => unawaited(controller.cancelImport()),
    ),
  if (!controller.isImportingAudio && controller.lastImportSummary != null)
    _Activity(
      'music-result',
      'Music import',
      controller.lastImportSummary!,
      complete: controller.importFailures.isEmpty,
    ),
  for (final task in controller.downloadTasks)
    _Activity(
      task.processId,
      task.title,
      task.isActive && task.progress == 0
          ? 'Connecting to audio source…'
          : task.isActive
          ? '${(task.progress * 100).floor()}% · ${_bytes(task.downloadedBytes ?? 0)} / ${_bytes(task.totalBytes ?? 0)}'
          : task.errorMessage ?? task.statusLabel,
      active: task.isActive,
      complete: task.status == DownloadTaskStatus.completed,
      progress: task.progress > 0 ? task.progress.clamp(0, 1) : null,
      cancel: task.isActive || task.status == DownloadTaskStatus.paused
          ? () => unawaited(controller.cancelDownload(task.processId))
          : null,
    ),
  if (service.isDownloading || service.downloaded != null)
    _Activity(
      'app-update',
      'Monolith update',
      service.status,
      active: service.isDownloading,
      complete: service.downloaded != null && !service.isDownloading,
      progress: service.progress != null && service.progress! > 0
          ? service.progress
          : null,
      cancel: service.isDownloading ? service.cancelDownload : null,
    ),
];

String _bytes(int value) => value >= 1024 * 1024
    ? '${(value / (1024 * 1024)).toStringAsFixed(1)} MB'
    : '${(value / 1024).toStringAsFixed(0)} KB';

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.job});
  final _Activity job;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 0, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  job.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  job.detail,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (job.active)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(value: job.progress),
                  ),
              ],
            ),
          ),
          if (job.cancel != null)
            IconButton(
              key: Key('stop-${job.id}'),
              tooltip: 'Stop ${job.title}',
              onPressed: job.cancel,
              icon: Icon(Icons.stop_rounded, color: scheme.primary, size: 20),
            )
          else
            Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(
                job.complete ? Icons.check_rounded : Icons.info_outline_rounded,
                size: 18,
                color: job.complete ? Colors.green : scheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}
