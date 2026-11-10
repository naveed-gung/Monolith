import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app/state/app_scope.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../core/models/music_models.dart';
import '../../../core/services/nearby/nearby_channel.dart';
import '../../../core/services/nearby/nearby_discovery.dart';
import '../../../core/services/nearby/nearby_platform.dart';
import '../../../core/services/nearby/nearby_session.dart';
import '../../../core/services/nearby/nearby_transfer.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_icons.dart';

enum _SendPhase { idle, preparing, connecting, waitingConsent, sending, done }

/// Share → Monolith app → discovered device picker → Send. Discovery runs only
/// while this page is open; leaving or cancelling stops the scan and any
/// pending socket work.
class NearbySharePage extends StatefulWidget {
  const NearbySharePage({super.key, required this.track});

  final Track track;

  @override
  State<NearbySharePage> createState() => _NearbySharePageState();
}

class _NearbySharePageState extends State<NearbySharePage> {
  final NearbyCancel _cancel = NearbyCancel();
  final List<NearbyPeer> _peers = [];
  bool _scanning = true;
  String? _scanError;
  Timer? _rescanTimer;
  bool _disposed = false;

  _SendPhase _phase = _SendPhase.idle;
  NearbyPeer? _target;
  String? _error;
  int _sent = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    unawaited(NearbyPlatform.acquireMulticastLock());
    unawaited(_scanLoop());
  }

  @override
  void dispose() {
    _disposed = true;
    _rescanTimer?.cancel();
    _cancel.cancel();
    unawaited(NearbyPlatform.releaseMulticastLock());
    super.dispose();
  }

  /// A scan lasts two seconds; scans repeat after five seconds without
  /// disabling controls or resetting the selection.
  Future<void> _scanLoop() async {
    while (!_disposed) {
      try {
        final found = await nearbyDiscover(cancel: _cancel);
        if (_disposed) return;
        setState(() {
          _peers
            ..clear()
            ..addAll(found);
          _scanning = false;
          _scanError = null;
        });
      } catch (error) {
        if (_disposed) return;
        setState(() {
          _scanning = false;
          _scanError = 'Discovery failed: $error';
        });
      }
      if (_disposed) return;
      final waiting = Completer<void>();
      _rescanTimer = Timer(const Duration(seconds: 5), waiting.complete);
      await Future.any([waiting.future, _cancel.onCancel]);
    }
  }

  Future<void> _rescan() async {
    _rescanTimer?.cancel();
    setState(() => _scanning = true);
    try {
      final found = await nearbyDiscover(cancel: _cancel);
      if (_disposed) return;
      setState(() {
        _peers
          ..clear()
          ..addAll(found);
        _scanning = false;
        _scanError = null;
      });
    } catch (error) {
      if (_disposed) return;
      setState(() {
        _scanning = false;
        _scanError = 'Discovery failed: $error';
      });
    }
  }

  Future<void> _send(NearbyPeer peer) async {
    if (_phase != _SendPhase.idle && _phase != _SendPhase.done) return;
    setState(() {
      _target = peer;
      _phase = _SendPhase.preparing;
      _error = null;
      _sent = 0;
      _total = 0;
    });
    NearbyChannel? channel;
    try {
      final file = File(widget.track.filePath ?? '');
      final offer = await nearbyOfferForFile(file, widget.track.title);
      if (_disposed) return;
      setState(() {
        _phase = _SendPhase.connecting;
        _total = offer.size;
      });
      channel = await nearbyConnect(peer, _cancel);
      if (_disposed) return;
      setState(() => _phase = _SendPhase.waitingConsent);
      await nearbySend(channel, file, offer, onProgress: (sent, total) {
        if (_disposed) return;
        setState(() {
          _phase = _SendPhase.sending;
          _sent = sent;
          _total = total;
        });
      });
      if (_disposed) return;
      setState(() => _phase = _SendPhase.done);
    } catch (error) {
      if (_disposed) return;
      setState(() {
        _phase = _SendPhase.idle;
        _error = _friendlyError(error);
      });
    } finally {
      unawaited(channel?.close());
    }
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('declined')) {
      return '${_target?.name ?? 'The device'} declined this song.';
    }
    if (text.contains('certificate changed')) {
      return 'Device certificate changed. Refresh nearby devices and try '
          'again. No song was sent.';
    }
    if (text.contains('cancelled')) return 'Sharing cancelled.';
    return 'Sharing failed: $text';
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.read(context);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final sending = _phase != _SendPhase.idle && _phase != _SendPhase.done;

    return PopScope(
      canPop: !sending,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _cancel.cancel();
        Navigator.of(context).maybePop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Monolith app'),
          actions: [
            IconButton(
              tooltip: 'Refresh nearby devices',
              onPressed: _scanning ? null : _rescan,
              icon: PhosphorIcon(AppIcons.refresh, size: 20),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenInset,
              AppSpacing.md,
              AppSpacing.screenInset,
              AppSpacing.xxxl,
            ),
            children: [
              Row(
                children: [
                  PhosphorIcon(
                    PhosphorIcons.musicNote(),
                    size: 18,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      '${widget.track.title} • ${widget.track.artist}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: AppType.label,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_phase != _SendPhase.idle) _SendStatus(
                phase: _phase,
                peer: _target,
                sent: _sent,
                total: _total,
                onCancel: sending
                    ? () {
                        controller.hapticLight();
                        _cancel.cancel();
                        setState(() => _phase = _SendPhase.idle);
                      }
                    : null,
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
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _scanning
                          ? 'Looking for Monolith devices…'
                          : 'Nearby devices',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: AppType.title,
                      ),
                    ),
                  ),
                  if (_scanning)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              if (_scanError != null)
                Text(
                  _scanError!,
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              if (!_scanning && _peers.isEmpty && _scanError == null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.xl,
                  ),
                  child: Text(
                    'No devices found. Open Monolith on the other device and '
                    'choose Share → Monolith app → Receive on the same Wi-Fi '
                    'network.',
                    style: textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              for (final peer in _peers)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _PeerTile(
                    peer: peer,
                    enabled: !sending && _phase != _SendPhase.done,
                    onTap: () {
                      controller.hapticSelection();
                      unawaited(_send(peer));
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PeerTile extends StatelessWidget {
  const _PeerTile({
    required this.peer,
    required this.enabled,
    required this.onTap,
  });

  final NearbyPeer peer;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      onTap: enabled ? onTap : null,
      child: Row(
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
                PhosphorIcons.devices(),
                size: 20,
                color: scheme.primary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              peer.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: AppType.label),
            ),
          ),
          PhosphorIcon(
            AppIcons.caretRight,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _SendStatus extends StatelessWidget {
  const _SendStatus({
    required this.phase,
    required this.peer,
    required this.sent,
    required this.total,
    required this.onCancel,
  });

  final _SendPhase phase;
  final NearbyPeer? peer;
  final int sent;
  final int total;
  final VoidCallback? onCancel;

  String _formatBytes(int bytes) {
    if (bytes >= 1000000) {
      return '${(bytes / 1000000).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1000) return '${(bytes / 1000).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final label = switch (phase) {
      _SendPhase.preparing => 'Preparing song…',
      _SendPhase.connecting => 'Connecting to ${peer?.name ?? 'device'}…',
      _SendPhase.waitingConsent =>
        'Waiting for ${peer?.name ?? 'the device'} to accept…',
      _SendPhase.sending =>
        'Sending to ${peer?.name ?? 'device'} — '
            '${_formatBytes(sent)} of ${_formatBytes(total)}',
      _SendPhase.done => 'Saved to ${peer?.name ?? 'the device'}\'s library.',
      _SendPhase.idle => '',
    };
    final progress = phase == _SendPhase.sending && total > 0
        ? sent / total
        : null;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: AppType.label,
                  ),
                ),
              ),
              if (onCancel != null)
                TextButton(
                  onPressed: onCancel,
                  child: const Text('Cancel'),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          RepaintBoundary(
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: scheme.outlineVariant.withValues(alpha: 0.3),
              valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
            ),
          ),
        ],
      ),
    );
  }
}
