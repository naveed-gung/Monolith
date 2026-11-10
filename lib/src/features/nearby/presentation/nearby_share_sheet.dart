import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../core/models/music_models.dart';
import '../../../core/widgets/app_icons.dart';
import 'nearby_receive_page.dart';
import 'nearby_share_page.dart';

/// Song action → Share → chooser. "Monolith app" sends the song directly to a
/// discovered Monolith device over the local network; "Other apps" keeps the
/// system share sheet; "Receive" opens the five-minute foreground session.
Future<void> showTrackShareSheet(BuildContext context, Track track) async {
  final action = await showModalBottomSheet<_ShareTarget>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: PhosphorIcon(PhosphorIcons.wifiHigh()),
              title: const Text('Monolith app'),
              subtitle: const Text('Send to a nearby Monolith device'),
              onTap: () => Navigator.pop(ctx, _ShareTarget.monolith),
            ),
            ListTile(
              leading: PhosphorIcon(PhosphorIcons.downloadSimple()),
              title: const Text('Receive'),
              subtitle: const Text('Let another Monolith device send to you'),
              onTap: () => Navigator.pop(ctx, _ShareTarget.receive),
            ),
            ListTile(
              leading: PhosphorIcon(AppIcons.share),
              title: const Text('Other apps'),
              subtitle: const Text('System share sheet'),
              onTap: () => Navigator.pop(ctx, _ShareTarget.system),
            ),
          ],
        ),
      ),
    ),
  );

  if (!context.mounted) return;
  switch (action) {
    case _ShareTarget.monolith:
      final fp = track.filePath;
      if (fp == null || fp.trim().isEmpty) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text(
              'Only songs stored on this device can be sent to Monolith.',
            ),
          ),
        );
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => NearbySharePage(track: track),
        ),
      );
    case _ShareTarget.receive:
      await Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const NearbyReceivePage()));
    case _ShareTarget.system:
      await shareTrackWithSystem(track);
    case null:
      break;
  }
}

/// The pre-existing system share-sheet path, kept unchanged.
Future<void> shareTrackWithSystem(Track track) async {
  final fp = track.filePath;
  if (fp != null && fp.trim().isNotEmpty) {
    await Share.shareXFiles([
      XFile(fp),
    ], text: '${track.title} • ${track.artist}');
  } else {
    await Share.share('${track.title} • ${track.artist}');
  }
}

enum _ShareTarget { monolith, receive, system }
