import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../core/models/music_models.dart';
import '../../../core/widgets/app_icons.dart';
import 'nearby_page.dart';

/// Song action → Share → chooser. "Nearby Monolith" opens the sharing hub with
/// the song preselected (the hub also receives while open); "Other apps" keeps
/// the system share sheet.
Future<void> showTrackShareSheet(BuildContext context, Track track) async {
  final canSend = nearbyCanSend(track);
  final action = await showModalBottomSheet<_ShareTarget>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: PhosphorIcon(PhosphorIcons.broadcast()),
              title: const Text('Nearby Monolith'),
              subtitle: Text(
                canSend
                    ? 'Send with cover art to a phone or computer on this Wi-Fi'
                    : 'Only songs stored on this device can be sent',
              ),
              enabled: canSend,
              onTap: () => Navigator.pop(ctx, _ShareTarget.monolith),
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
      await openNearbyPage(context, tracks: [track]);
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

enum _ShareTarget { monolith, system }
