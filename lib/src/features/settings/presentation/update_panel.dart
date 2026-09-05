import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/services/app_update_service.dart';

class UpdatePanel extends StatelessWidget {
  const UpdatePanel({super.key});
  Future<void> _install(BuildContext context, AppUpdateService service) async {
    try {
      if (Platform.isIOS) {
        final opened = await launchUrl(
          Uri(
            scheme: 'apple-magnifier',
            host: 'install',
            queryParameters: {'url': service.release!.url.toString()},
          ),
          mode: LaunchMode.externalApplication,
        );
        if (!opened) {
          throw StateError('Enable URL Scheme in TrollStore settings.');
        }
      } else {
        await const MethodChannel(
          'monolith/updates',
        ).invokeMethod<void>('install', {'path': service.downloaded!.path});
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
