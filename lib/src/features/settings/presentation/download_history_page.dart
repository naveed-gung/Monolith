import 'package:flutter/material.dart';
import '../../../app/state/app_scope.dart';
import '../../../core/models/music_models.dart';

class DownloadHistoryPage extends StatefulWidget {
  const DownloadHistoryPage({super.key});
  @override
  State<DownloadHistoryPage> createState() => _DownloadHistoryPageState();
}

class _DownloadHistoryPageState extends State<DownloadHistoryPage> {
  String? _busyUrl;
  bool _fetching = false;

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _download(DownloadHistoryEntry entry) async {
    if (_busyUrl != null) return;
    final controller = AppScope.read(context);
    setState(() => _busyUrl = entry.url);
    try {
      final existing = await controller.downloadedTrackForUrl(entry.url);
      if (!mounted) return;
      if (existing != null) {
        final replace = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('You already have this song'),
            content: Text(
              'Get a fresh copy of “${existing.title}”? Your saved copy is replaced only after the new download succeeds.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Get anyway'),
              ),
            ],
          ),
        );
        if (replace != true || !mounted) return;
      }
      setState(() => _fetching = true);
      await controller.redownloadHistoryEntry(
        entry,
        replaceExisting: existing != null,
      );
      _message('Download added. Follow its progress in Downloads.');
    } catch (error) {
      _message(error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _busyUrl = null;
          _fetching = false;
        });
      }
    }
  }

  Future<void> _clear() async {
    final controller = AppScope.read(context);
    final clear = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear download history?'),
        content: const Text(
          'Saved songs stay in your library. Only these names and links are removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (clear != true) return;
    try {
      await controller.clearDownloadHistory();
    } catch (_) {
      _message('Could not clear history. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final history = AppScope.watch(context).downloadHistory;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Download history'),
        actions: [
          TextButton(
            onPressed: history.isEmpty || _busyUrl != null ? null : _clear,
            child: const Text('Clear'),
          ),
        ],
      ),
      body: history.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Your download links will appear here.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.only(top: 12, bottom: 32),
              itemCount: history.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, indent: 24, endIndent: 24),
              itemBuilder: (context, index) {
                final entry = history[index];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 8,
                  ),
                  title: Text(
                    entry.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    entry.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: _fetching && _busyUrl == entry.url
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_outlined),
                  onTap: _busyUrl == null ? () => _download(entry) : null,
                );
              },
            ),
    );
  }
}
