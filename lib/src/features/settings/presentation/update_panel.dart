import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/services/app_update_service.dart';

class UpdatePanel extends StatelessWidget {
  const UpdatePanel({super.key});

  Future<void> _showRestartDialog(BuildContext context) async {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Update installed'),
        content: const Text(
          'Monolith has been updated. Would you like to restart the app now or continue and restart later?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => exit(0),
            child: const Text('Restart now'),
          ),
        ],
      ),
    );
  }

  Future<void> _install(BuildContext context, AppUpdateService service) async {
    try {
      if (Platform.isIOS) {
        if (service.downloaded != null) {
          final box = context.findRenderObject() as RenderBox?;
          await Share.shareXFiles(
            [XFile(service.downloaded!.path)],
            text: 'Install Monolith update',
            sharePositionOrigin: box == null
                ? null
                : box.localToGlobal(Offset.zero) & box.size,
          );
          return;
        }

        // If update not downloaded yet, trigger download first
        if (service.release != null) {
          await service.download();
          if (service.downloaded != null && context.mounted) {
            final box = context.findRenderObject() as RenderBox?;
            await Share.shareXFiles(
              [XFile(service.downloaded!.path)],
              text: 'Install Monolith update',
              sharePositionOrigin: box == null
                  ? null
                  : box.localToGlobal(Offset.zero) & box.size,
            );
            return;
          }
        }

        var opened = await launchUrl(
          Uri(
            scheme: 'apple-magnifier',
            host: 'install',
            queryParameters: {'url': service.release!.url.toString()},
          ),
          mode: LaunchMode.externalApplication,
        );
        if (!opened) {
          // Try AltStore URL scheme
          opened = await launchUrl(
            Uri.parse('altstore://install?url=${service.release!.url}'),
            mode: LaunchMode.externalApplication,
          );
        }
        if (!opened) {
          throw StateError(
            'Could not open installer. Open TrollStore, AltStore, or share the IPA.',
          );
        }
      } else {
        await const MethodChannel(
          'monolith/updates',
        ).invokeMethod<void>('install', {'path': service.downloaded!.path});
      }

      if (context.mounted) {
        await _showRestartDialog(context);
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open installer. $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = AppUpdateService.instance;
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
                if (service.release != null &&
                    (Platform.isIOS || service.downloaded != null))
                  FilledButton(
                    onPressed: service.busy
                        ? null
                        : () => _install(context, service),
                    child: Text(
                      Platform.isIOS
                          ? 'Install with TrollStore'
                          : 'Install update',
                    ),
                  ),
                if (Platform.isIOS && service.downloaded != null)
                  TextButton(
                    onPressed: () {
                      final box = context.findRenderObject() as RenderBox?;
                      Share.shareXFiles(
                        [XFile(service.downloaded!.path)],
                        sharePositionOrigin: box == null
                            ? null
                            : box.localToGlobal(Offset.zero) & box.size,
                      );
                    },
                    child: const Text('Open downloaded IPA…'),
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
              Platform.isIOS
                  ? 'Enable URL Scheme in TrollStore. Install over Monolith to retain music. The downloaded IPA is also available above.'
                  : 'Install over the existing app to keep your music. Updates must use the same signing key.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
