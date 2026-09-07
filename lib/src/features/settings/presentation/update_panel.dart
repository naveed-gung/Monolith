import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/services/app_update_service.dart';

class UpdatePanel extends StatelessWidget {
  const UpdatePanel({super.key, this.service});
  final AppUpdateService? service;

  Future<void> _openPackage(
    BuildContext context,
    AppUpdateService service,
  ) async {
    final file = service.downloaded;
    if (file == null || !await file.exists()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The downloaded package is missing. Download it again.',
            ),
          ),
        );
      }
      return;
    }
    if (!context.mounted) return;
    try {
      if (service.isIOS) {
        final box = context.findRenderObject() as RenderBox?;
        await Share.shareXFiles(
          [XFile(file.path)],
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        );
      } else {
        await const MethodChannel(
          'monolith/updates',
        ).invokeMethod<void>('install', {'path': file.path});
      }
      // Opening the installer/share sheet does not prove installation succeeded.
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not open the package. It remains saved for another try.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = this.service ?? AppUpdateService.instance;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Keep Monolith current',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(service.status),
            Material(
              color: Colors.transparent,
              child: SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Auto-download on Wi-Fi'),
                subtitle: const Text('Installation stays in your control'),
                value: service.autoDownload,
                onChanged: service.setAutomatic,
              ),
            ),
            if (service.busy) LinearProgressIndicator(value: service.progress),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: service.busy ? null : service.check,
                  child: const Text('Check for updates'),
                ),
                if (service.release != null && service.downloaded == null)
                  FilledButton(
                    onPressed: service.busy ? null : service.download,
                    child: const Text('Download update'),
                  ),
                if (service.downloaded != null) ...[
                  FilledButton(
                    onPressed: () => _openPackage(context, service),
                    child: Text(
                      service.isIOS ? 'Open downloaded IPA…' : 'Install update',
                    ),
                  ),
                  if (service.isIOS)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Choose TrollStore in the share sheet, or Save to Files and open the IPA there. The package is already downloaded.',
                      ),
                    ),
                ],
                if (service.isDownloading)
                  TextButton(
                    onPressed: service.cancelDownload,
                    child: const Text('Cancel download'),
                  ),
                TextButton.icon(
                  icon: const Icon(Icons.cleaning_services_outlined, size: 16),
                  onPressed: () async {
                    final freed = await service.clearStaleAppCache();
                    if (context.mounted) {
                      final mb = (freed / (1024 * 1024)).toStringAsFixed(1);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Freed $mb MB of cache. Your music & custom settings remain intact.',
                          ),
                        ),
                      );
                    }
                  },
                  label: const Text('Clean app cache'),
                ),
              ],
            ),
            Text(
              service.isIOS
                  ? 'In TrollStore, replace the installed Monolith app to retain your music. Do not uninstall it first.'
                  : 'Install over the existing app to keep your music. Updates must use the same signing key.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
