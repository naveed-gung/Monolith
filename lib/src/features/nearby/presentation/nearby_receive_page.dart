import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app/state/app_scope.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../core/services/download_store.dart';
import '../../../core/services/nearby/nearby_channel.dart';
import '../../../core/services/nearby/nearby_platform.dart';
import '../../../core/services/nearby/nearby_session.dart';
import '../../../core/services/nearby/nearby_transfer.dart';
import '../../../core/services/nearby/nearby_wire.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_icons.dart';

/// Receive — a five-minute foreground session. The TLS listener and UDP
/// discovery responder exist only while this page is open; each song asks for
/// explicit consent before a single byte is accepted. Close/Cancel aborts
/// active sockets and stops advertising.
class NearbyReceivePage extends StatefulWidget {
  const NearbyReceivePage({super.key});

  @override
  State<NearbyReceivePage> createState() => _NearbyReceivePageState();
}

class _NearbyReceivePageState extends State<NearbyReceivePage> {
  static const _sessionLength = Duration(minutes: 5);

  final NearbyCancel _cancel = NearbyCancel();
  final DownloadStore _store = DownloadStore();
  NearbyReceiver? _receiver;
  String? _error;
  bool _disposed = false;
  late DateTime _endsAt;
  Timer? _ticker;
  Duration _remaining = _sessionLength;

  String _status = 'Starting…';
  NearbyOffer? _activeOffer;
  int _received = 0;
  int _savedCount = 0;

  @override
  void initState() {
    super.initState();
    _endsAt = DateTime.now().add(_sessionLength);
    unawaited(NearbyPlatform.acquireMulticastLock());
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    unawaited(_run());
  }

  void _tick() {
    if (_disposed) return;
    final remaining = _endsAt.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      setState(() {
        _remaining = Duration.zero;
        _status = 'Session ended.';
      });
      _cancel.cancel();
      return;
    }
    setState(() => _remaining = remaining);
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _cancel.cancel();
    unawaited(_receiver?.close());
    unawaited(NearbyPlatform.releaseMulticastLock());
    super.dispose();
  }

  Future<void> _run() async {
    try {
      final receiver = await NearbyReceiver.start(cancel: _cancel);
      _receiver = receiver;
      if (_disposed) return;
      setState(() => _status = 'Visible as “${receiver.alias}”');
      while (true) {
        final channel = await receiver.accept();
        if (channel == null) return;
        await _handle(channel);
      }
    } catch (error) {
      if (_disposed) return;
      setState(() {
        _status = 'Receive unavailable.';
        _error = '$error';
      });
    }
  }

  Future<void> _handle(NearbyChannel channel) async {
    try {
      final staged = await getTemporaryDirectory().then(
        (dir) => Directory(
          '${dir.path}${Platform.pathSeparator}monolith-receive',
        ),
      );
      await nearbyReceive(
        channel,
        staged,
        consent: (offer, sender) => _askConsent(offer, sender),
        publish: (file, name) => _publish(file, name),
        import: (_) async {
          final controller = AppScope.read(context);
          await controller.refreshLibrary();
        },
        onProgress: (received, total) {
          if (_disposed) return;
          setState(() => _received = received);
        },
      );
      if (_disposed) return;
      setState(() {
        _savedCount += 1;
        _activeOffer = null;
        _status = 'Waiting for the next song…';
      });
    } catch (error) {
      if (_disposed) return;
      setState(() {
        _activeOffer = null;
        _status = 'Waiting for the next song…';
        _error = error.toString().contains('declined')
            ? 'Song declined.'
            : 'Transfer failed: $error';
      });
    } finally {
      _receiver?.release(channel);
      unawaited(channel.close());
    }
  }

  Future<File> _publish(File staged, String name) async {
    final published = await _store.saveImportedAudio(
      preferredFileName: name,
      sourcePath: staged.path,
    );
    // A partial platform copy must never reach the library.
    if (await published.length() != await staged.length()) {
      await published.delete().catchError((Object _) => published);
      throw const SocketException('The received song could not be saved.');
    }
    return published;
  }

  Future<bool> _askConsent(NearbyOffer offer, String sender) async {
    if (_disposed || !mounted) return false;
    setState(() => _activeOffer = offer);
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ConsentDialog(offer: offer, sender: sender),
    );
    if (_disposed) return false;
    setState(() {
      _received = 0;
      if (accepted == true) {
        _status = 'Receiving “${offer.title}”…';
      }
    });
    return accepted == true;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final minutes = _remaining.inMinutes;
    final seconds = (_remaining.inSeconds % 60).toString().padLeft(2, '0');

    return Scaffold(
      appBar: AppBar(title: const Text('Receive songs')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenInset,
            AppSpacing.md,
            AppSpacing.screenInset,
            AppSpacing.xxxl,
          ),
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.12),
                          borderRadius: AppRadii.all(AppRadii.md),
                        ),
                        child: Center(
                          child: PhosphorIcon(
                            PhosphorIcons.wifiHigh(),
                            size: 20,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _status,
                              style: textTheme.titleSmall?.copyWith(
                                fontWeight: AppType.label,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Same Wi-Fi • session ends in $minutes:$seconds',
                              style: textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_activeOffer != null && _received > 0) ...[
                    const SizedBox(height: AppSpacing.md),
                    RepaintBoundary(
                      child: LinearProgressIndicator(
                        value: _received / _activeOffer!.size,
                        minHeight: 4,
                        backgroundColor: scheme.outlineVariant.withValues(
                          alpha: 0.3,
                        ),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          scheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${(_received / 1000000).toStringAsFixed(1)} of '
                      '${(_activeOffer!.size / 1000000).toStringAsFixed(1)} MB',
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (_savedCount > 0) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      '$_savedCount ${_savedCount == 1 ? 'song' : 'songs'} '
                      'saved to your library.',
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: AppType.label,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              AppCard(
                color: scheme.errorContainer.withValues(alpha: 0.35),
                child: Text(
                  _error!,
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onErrorContainer,
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            Text(
              'On the other device, choose Share → Monolith app and tap this '
              'device. You approve every song before it arrives; nothing is '
              'accepted while this page is closed.',
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  _cancel.cancel();
                  Navigator.of(context).maybePop();
                },
                icon: PhosphorIcon(AppIcons.close, size: 18),
                label: const Text('Stop receiving'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Per-song consent with the sender label, title, filename and actual size.
/// The 60-second countdown matches the desktop consent timeout — expiry is a
/// decline.
class _ConsentDialog extends StatefulWidget {
  const _ConsentDialog({required this.offer, required this.sender});

  final NearbyOffer offer;
  final String sender;

  @override
  State<_ConsentDialog> createState() => _ConsentDialogState();
}

class _ConsentDialogState extends State<_ConsentDialog> {
  int _secondsLeft = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsLeft <= 1) {
        timer.cancel();
        Navigator.of(context).pop(false);
        return;
      }
      setState(() => _secondsLeft -= 1);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final offer = widget.offer;
    final sizeMb = (offer.size / 1000000).toStringAsFixed(1);
    return AlertDialog(
      title: const Text('Accept song?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            offer.title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: AppType.title),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${offer.name} • $sizeMb MB\nfrom ${widget.sender}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Declining automatically in $_secondsLeft s',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Decline'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Accept'),
        ),
      ],
    );
  }
}
