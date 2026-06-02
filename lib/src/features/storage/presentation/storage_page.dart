import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/state/app_scope.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../core/models/music_models.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/track_artwork.dart';

class StoragePage extends StatefulWidget {
  const StoragePage({super.key});

  @override
  State<StoragePage> createState() => _StoragePageState();
}

class _StoragePageState extends State<StoragePage> {
  String? _directoryPath;
  bool _loadingPath = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadingPath) _loadPath();
  }

  Future<void> _loadPath() async {
    final controller = AppScope.read(context);
    final path = await controller.getDownloadDirectoryPath();
    if (mounted) setState(() { _directoryPath = path; _loadingPath = false; });
  }

  Future<void> _shareFile(Track track) async {
    final fp = track.filePath;
    if (fp == null || fp.isEmpty) return;
    await Share.shareXFiles(
      [XFile(fp)],
      text: '${track.title} • ${track.artist}',
    );
  }

  Future<void> _openDirectory() async {
    final path = _directoryPath;
    if (path == null) return;

    if (Platform.isAndroid) {
      // External app storage lives under /storage/emulated/0/Android/data/<pkg>/files.
      // The DocumentsProvider for primary external storage maps paths like:
      //   primary:Android/data/<pkg>/files/downloads
      // which becomes the content URI below. Files by Google and Samsung My Files
      // both handle this URI and navigate to the exact folder.
      const extRoot = '/storage/emulated/0/';
      if (path.startsWith(extRoot)) {
        // Uri(pathSegments:) encodes '/' within each segment as %2F, keeping ':'
        // as-is — exactly the format the DocumentsProvider expects for doc IDs.
        final ok = await launchUrl(
          Uri(
            scheme: 'content',
            host: 'com.android.externalstorage.documents',
            pathSegments: ['document', 'primary:${path.substring(extRoot.length)}'],
          ),
          mode: LaunchMode.externalApplication,
        );
        if (ok) return;
      }
      // Path is in internal storage (pre-migration installs) — file manager
      // cannot access it; show the path so the user can copy it manually.
      if (mounted) _showCopyPath(path);
    } else if (Platform.isIOS) {
      await Share.shareXFiles([XFile(path)]);
    }
  }

  void _showCopyPath(String path) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(path, maxLines: 2, overflow: TextOverflow.ellipsis),
        action: SnackBarAction(
          label: 'Copy',
          onPressed: () => Clipboard.setData(ClipboardData(text: path)),
        ),
      ),
    );
  }

  String _fmtBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  int _fileSize(String? path) {
    if (path == null) return 0;
    try { return File(path).lengthSync(); } catch (_) { return 0; }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tracks = controller.offlineTracks;
    final totalBytes = tracks.fold<int>(0, (sum, t) => sum + _fileSize(t.filePath));

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: PhosphorIcon(PhosphorIcons.caretLeft(), size: 22, color: scheme.onSurface),
          tooltip: 'Back',
        ),
      ),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── Header ──────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenInset, AppSpacing.md,
                AppSpacing.screenInset, AppSpacing.xxl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Storage',
                    style: textTheme.displaySmall?.copyWith(
                      fontWeight: AppType.display,
                      letterSpacing: AppType.trackTight,
                    )),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${tracks.length} file${tracks.length == 1 ? '' : 's'} · ${_fmtBytes(totalBytes)}',
                    style: textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),

          // ── Directory card ───────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenInset, 0, AppSpacing.screenInset, AppSpacing.xl,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: AppRadii.all(AppRadii.lg),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.5), width: 0.5),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Row(
                        children: [
                          Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              borderRadius: AppRadii.all(AppRadii.sm),
                            ),
                            child: Center(child: PhosphorIcon(
                              PhosphorIcons.folder(), size: 20,
                              color: scheme.onPrimaryContainer,
                            )),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Download folder',
                                  style: textTheme.bodyLarge?.copyWith(fontWeight: AppType.body)),
                                if (_directoryPath != null)
                                  Text(_directoryPath!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                      fontFamily: 'monospace',
                                    )),
                                if (_loadingPath)
                                  Text('Loading…',
                                    style: textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.4)),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: _directoryPath != null
                                ? () => Clipboard.setData(ClipboardData(text: _directoryPath!))
                                : null,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.md, horizontal: AppSpacing.lg),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  PhosphorIcon(PhosphorIcons.copy(), size: 16,
                                    color: scheme.primary),
                                  const SizedBox(width: AppSpacing.sm),
                                  Text('Copy path',
                                    style: textTheme.labelMedium?.copyWith(
                                      color: scheme.primary, fontWeight: AppType.label)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        VerticalDivider(
                          width: 1, color: scheme.outlineVariant.withValues(alpha: 0.4)),
                        Expanded(
                          child: InkWell(
                            onTap: _openDirectory,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.md, horizontal: AppSpacing.lg),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  PhosphorIcon(PhosphorIcons.folderOpen(), size: 16,
                                    color: scheme.primary),
                                  const SizedBox(width: AppSpacing.sm),
                                  Text('Open in Files',
                                    style: textTheme.labelMedium?.copyWith(
                                      color: scheme.primary, fontWeight: AppType.label)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── File list ────────────────────────────────────────────────────
          if (tracks.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xxxl),
                child: Column(
                  children: [
                    PhosphorIcon(PhosphorIcons.folderSimpleDashed(),
                      size: 52, color: scheme.onSurfaceVariant),
                    const SizedBox(height: AppSpacing.md),
                    Text('No downloaded files',
                      style: textTheme.titleMedium?.copyWith(
                        color: scheme.onSurfaceVariant)),
                    const SizedBox(height: AppSpacing.xs),
                    Text('Files will appear here after you download music.',
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenInset, 0, AppSpacing.screenInset, 120),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: Text('Downloaded files',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: AppType.title,
                            letterSpacing: AppType.trackSnug,
                          )),
                      );
                    }
                    final track = tracks[index - 1];
                    final size = _fileSize(track.filePath);
                    final isLast = index == tracks.length;
                    return _FileRow(
                      track: track,
                      sizeLabel: size > 0 ? _fmtBytes(size) : '—',
                      onShare: () => _shareFile(track),
                      showDivider: !isLast,
                    );
                  },
                  childCount: tracks.length + 1,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.track,
    required this.sizeLabel,
    required this.onShare,
    required this.showDivider,
  });

  final Track track;
  final String sizeLabel;
  final VoidCallback onShare;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final ext = track.filePath?.split('.').last.toUpperCase() ?? '';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm + AppSpacing.xs),
          child: Row(
            children: [
              SizedBox(
                width: 48, height: 48,
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
                    Text(track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyLarge?.copyWith(fontWeight: AppType.body)),
                    Row(
                      children: [
                        if (ext.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(right: AppSpacing.xs),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHigh,
                              borderRadius: AppRadii.all(AppRadii.sm),
                            ),
                            child: Text(ext,
                              style: textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontWeight: AppType.label,
                              )),
                          ),
                        Text(sizeLabel,
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onShare,
                tooltip: 'Share / Open in Files',
                icon: PhosphorIcon(
                  AppIcons.share, size: 20,
                  color: scheme.onSurfaceVariant),
                padding: const EdgeInsets.all(AppSpacing.sm),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(height: 1, indent: 64,
            color: scheme.outlineVariant.withValues(alpha: 0.35)),
      ],
    );
  }
}
