import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app/state/app_scope.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../core/models/music_models.dart';
import '../../../core/services/download_store.dart';
import '../../../core/services/nearby/nearby_channel.dart';
import '../../../core/services/nearby/nearby_discovery.dart';
import '../../../core/services/nearby/nearby_platform.dart';
import '../../../core/services/nearby/nearby_session.dart';
import '../../../core/services/nearby/nearby_transfer.dart';
import '../../../core/services/nearby/nearby_wire.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/track_artwork.dart';

/// Opens the sharing hub, optionally with songs already chosen to send.
Future<void> openNearbyPage(
  BuildContext context, {
  List<Track> tracks = const [],
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => NearbyPage(initialTracks: tracks)),
  );
}

/// True when [track] is a file on this device that can be sent.
bool nearbyCanSend(Track track) =>
    (track.filePath ?? '').trim().isNotEmpty;

/// One screen for Monolith-to-Monolith sharing. While it is open this device
/// is discoverable (TLS listener + discovery responder) and keeps scanning for
/// other Monolith devices with this screen open, so both sides see each other
/// without choosing "send" or "receive" first. Every incoming song still needs
/// explicit consent; closing the screen stops advertising and aborts sockets.
class NearbyPage extends StatefulWidget {
  const NearbyPage({super.key, this.initialTracks = const []});

  final List<Track> initialTracks;

  @override
  State<NearbyPage> createState() => _NearbyPageState();
}

enum _ItemState { queued, connecting, waiting, sending, done, declined, failed }

class _BatchItem {
  _BatchItem(this.track);

  final Track track;
  _ItemState state = _ItemState.queued;
  int sent = 0;
  int total = 0;
  String? error;
}

class _SeenPeer {
  _SeenPeer(this.peer, this.lastSeen);

  NearbyPeer peer;
  DateTime lastSeen;
}

class _NearbyPageState extends State<NearbyPage> {
  /// A peer missing from this many seconds of scans drops off the list, so a
  /// single lost datagram never makes a device flicker.
  static const _peerTtl = Duration(seconds: 15);
  static const _scanPause = Duration(seconds: 3);

  final NearbyCancel _pageCancel = NearbyCancel();
  final DownloadStore _store = DownloadStore();
  bool _disposed = false;

  // Receiving side.
  NearbyReceiver? _receiver;
  String? _receiveError;
  NearbyOffer? _incoming;
  int _incomingReceived = 0;
  final List<String> _receivedTitles = [];

  // Discovery.
  final Map<String, _SeenPeer> _peers = {};
  bool _firstScanDone = false;
  bool _scanning = false;
  String? _scanError;
  Timer? _scanTimer;
  Completer<void>? _scanWake;

  // Sending side.
  late final List<Track> _selected = [...widget.initialTracks];
  List<_BatchItem> _batch = const [];
  NearbyPeer? _batchPeer;
  NearbyCancel? _batchCancel;

  bool get _batchActive =>
      _batch.any((item) => item.state.index <= _ItemState.sending.index) &&
      _batchCancel != null &&
      !_batchCancel!.cancelled;

  @override
  void initState() {
    super.initState();
    unawaited(NearbyPlatform.acquireMulticastLock());
    unawaited(_start());
  }

  @override
  void dispose() {
    _disposed = true;
    _scanTimer?.cancel();
    _batchCancel?.cancel();
    _pageCancel.cancel();
    unawaited(_receiver?.close());
    unawaited(NearbyPlatform.releaseMulticastLock());
    super.dispose();
  }

  void _update(VoidCallback change) {
    if (_disposed || !mounted) return;
    setState(change);
  }

  Future<void> _start() async {
    // Become visible first so the scan can drop this device's own reply.
    try {
      final receiver = await NearbyReceiver.start(cancel: _pageCancel);
      if (_disposed) {
        await receiver.close();
        return;
      }
      _update(() => _receiver = receiver);
      unawaited(_acceptLoop(receiver));
    } catch (error) {
      _update(() => _receiveError = _describeStartError(error));
    }
    await _scanLoop();
  }

  String _describeStartError(Object error) {
    final text = '$error';
    if (text.contains('Address already in use') || text.contains('errno = 98')) {
      return 'Another app is using the sharing port. Close other Monolith '
          'windows and reopen Share.';
    }
    return 'This device can send but is not visible to others right now.';
  }

  // ── Discovery ─────────────────────────────────────────────────────────

  Future<void> _scanLoop() async {
    while (!_disposed && !_pageCancel.cancelled) {
      await _scanOnce();
      if (_disposed) return;
      final wake = _scanWake = Completer<void>();
      _scanTimer = Timer(_scanPause, () {
        if (!wake.isCompleted) wake.complete();
      });
      await Future.any([wake.future, _pageCancel.onCancel]);
    }
  }

  Future<void> _scanOnce() async {
    _update(() => _scanning = true);
    try {
      final found = await nearbyDiscover(
        cancel: _pageCancel,
        ignoreFingerprint: _receiver?.fingerprint,
      );
      final now = DateTime.now();
      _update(() {
        for (final peer in found) {
          final seen = _peers[peer.id];
          if (seen == null) {
            _peers[peer.id] = _SeenPeer(peer, now);
          } else {
            seen
              ..peer = peer
              ..lastSeen = now;
          }
        }
        _peers.removeWhere(
          (id, seen) =>
              now.difference(seen.lastSeen) > _peerTtl && id != _batchPeer?.id,
        );
        _scanError = null;
      });
    } catch (error) {
      _update(() => _scanError = 'Could not search the network: $error');
    } finally {
      _update(() {
        _scanning = false;
        _firstScanDone = true;
      });
    }
  }

  void _rescanNow() {
    AppScope.read(context).hapticLight();
    _scanTimer?.cancel();
    final wake = _scanWake;
    if (wake != null && !wake.isCompleted) wake.complete();
  }

  // ── Receiving ─────────────────────────────────────────────────────────

  Future<void> _acceptLoop(NearbyReceiver receiver) async {
    try {
      while (!_disposed) {
        final channel = await receiver.accept();
        if (channel == null) return;
        await _handleIncoming(receiver, channel);
      }
    } catch (error) {
      _update(() => _receiveError = 'Receiving stopped: $error');
    }
  }

  Future<void> _handleIncoming(
    NearbyReceiver receiver,
    NearbyChannel channel,
  ) async {
    if (_disposed || !mounted) {
      receiver.release(channel);
      unawaited(channel.close());
      return;
    }
    final controller = AppScope.read(context);
    try {
      final staging = Directory(
        '${(await getTemporaryDirectory()).path}'
        '${Platform.pathSeparator}monolith-receive',
      );
      await nearbyReceive(
        channel,
        staging,
        consent: _askConsent,
        publish: _publish,
        saveArtwork: (published, bytes, ext) =>
            _store.saveSharedArtwork(published.path, bytes, ext),
        import: (_) => controller.refreshLibrary(),
        onProgress: (received, _) =>
            _update(() => _incomingReceived = received),
      );
      final title = _incoming?.title ?? 'Song';
      controller.hapticMedium();
      _update(() => _receivedTitles.insert(0, title));
      _snack('“$title” added to your library.');
    } catch (error) {
      final text = '$error';
      if (!text.contains('declined') && !_disposed) {
        _snack('Receiving failed. ${_plainError(error)}');
      }
    } finally {
      _update(() {
        _incoming = null;
        _incomingReceived = 0;
      });
      receiver.release(channel);
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
    AppScope.read(context).hapticMedium();
    final senderName = _peers.values
        .map((seen) => seen.peer)
        .where((peer) => peer.address.address == sender)
        .map(_alias)
        .firstOrNull;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ConsentDialog(
        offer: offer,
        sender: senderName == null ? sender : '$senderName ($sender)',
      ),
    );
    if (accepted == true) {
      _update(() {
        _incoming = offer;
        _incomingReceived = 0;
      });
    }
    return accepted == true;
  }

  // ── Sending ───────────────────────────────────────────────────────────

  Future<void> _pickSongs() async {
    final controller = AppScope.read(context);
    final picked = await showModalBottomSheet<List<Track>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => _SongPicker(
        tracks: controller.tracks.where(nearbyCanSend).toList(),
        initial: _selected,
      ),
    );
    if (picked == null) return;
    _update(() {
      _selected
        ..clear()
        ..addAll(picked);
    });
  }

  Future<void> _sendTo(NearbyPeer peer) async {
    if (_batchActive) return;
    if (_selected.isEmpty) {
      await _pickSongs();
      if (_selected.isEmpty || !mounted) return;
    }
    final controller = AppScope.read(context);
    controller.hapticSelection();
    final cancel = NearbyCancel();
    final batch = [for (final track in _selected) _BatchItem(track)];
    _update(() {
      _batchCancel = cancel;
      _batchPeer = peer;
      _batch = batch;
    });

    for (final item in batch) {
      if (cancel.cancelled || _disposed) break;
      await _sendOne(peer, item, cancel);
    }
    if (_disposed) return;
    final sent = batch.where((i) => i.state == _ItemState.done).length;
    if (sent > 0) controller.hapticMedium();
    _update(() {
      for (final item in batch) {
        if (item.state.index <= _ItemState.sending.index) {
          item
            ..state = _ItemState.failed
            ..error = 'Cancelled';
        }
      }
      _batchCancel = null;
    });
  }

  Future<void> _sendOne(
    NearbyPeer peer,
    _BatchItem item,
    NearbyCancel cancel,
  ) async {
    NearbyChannel? channel;
    try {
      _update(() => item.state = _ItemState.connecting);
      final file = File(item.track.filePath ?? '');
      final artworkPath =
          item.track.artworkFilePath ??
          await _store.findArtworkForAudio(file.path);
      final artwork = artworkPath == null ? null : File(artworkPath);
      final offer = await nearbyOfferForFile(
        file,
        item.track.title,
        artwork: artwork,
      );
      _update(() => item.total = offer.size);
      channel = await nearbyConnect(peer, cancel);
      _update(() => item.state = _ItemState.waiting);
      await nearbySend(
        channel,
        file,
        offer,
        artwork: artwork,
        onProgress: (sent, total) => _update(() {
          item
            ..state = _ItemState.sending
            ..sent = sent
            ..total = total;
        }),
      );
      _update(() => item.state = _ItemState.done);
    } catch (error) {
      final declined = '$error'.contains('declined');
      _update(() {
        item
          ..state = declined ? _ItemState.declined : _ItemState.failed
          ..error = declined ? null : _plainError(error);
      });
    } finally {
      unawaited(channel?.close());
    }
  }

  void _cancelBatch() {
    AppScope.read(context).hapticLight();
    _batchCancel?.cancel();
  }

  Future<bool> _confirmLeave() async {
    if (!_batchActive) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop sending?'),
        content: const Text(
          'Songs that have not finished will not reach the other device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep sending'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
    if (leave == true) _batchCancel?.cancel();
    return leave == true;
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  static String _alias(NearbyPeer peer) {
    final dot = peer.name.lastIndexOf(' · ');
    return dot == -1 ? peer.name : peer.name.substring(0, dot);
  }

  static String _plainError(Object error) {
    final text = '$error';
    if (text.contains('certificate changed')) {
      return 'The device restarted sharing. Wait for it to reappear and try '
          'again.';
    }
    if (text.contains('cancelled')) return 'Cancelled.';
    if (text.contains('under 100 MB')) return 'Songs over 100 MB cannot be sent.';
    if (text.contains('Connection refused') ||
        text.contains('timed out') ||
        text.contains('Timeout')) {
      return 'The device stopped responding. Check it still has Share open.';
    }
    if (text.contains('not running a compatible')) {
      return 'The other device needs to update Monolith.';
    }
    final colon = text.indexOf(': ');
    return colon == -1 ? text : text.substring(colon + 2);
  }

  void _snack(String message) {
    if (_disposed || !mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ── UI ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final peers = _peers.values.map((seen) => seen.peer).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return PopScope(
      canPop: !_batchActive,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Share with Monolith'),
          actions: [
            IconButton(
              tooltip: 'Search again',
              onPressed: _scanning ? null : _rescanNow,
              icon: PhosphorIcon(AppIcons.refresh, size: 20),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenInset,
              AppSpacing.sm,
              AppSpacing.screenInset,
              AppSpacing.xxxl,
            ),
            children: [
              _VisibilityCard(
                alias: _receiver?.alias,
                error: _receiveError,
                incoming: _incoming,
                received: _incomingReceived,
                receivedCount: _receivedTitles.length,
              ),
              const SizedBox(height: AppSpacing.xl),
              _SectionTitle(
                title: 'Songs to send',
                trailing: TextButton.icon(
                  onPressed: _batchActive ? null : _pickSongs,
                  icon: PhosphorIcon(
                    _selected.isEmpty ? AppIcons.add : AppIcons.edit,
                    size: 16,
                  ),
                  label: Text(_selected.isEmpty ? 'Choose' : 'Change'),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              _SelectedSongs(
                tracks: _selected,
                onPick: _batchActive ? null : _pickSongs,
                onRemove: _batchActive
                    ? null
                    : (track) => _update(() => _selected.remove(track)),
              ),
              if (_batch.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                _BatchCard(
                  peerName: _batchPeer == null ? '' : _alias(_batchPeer!),
                  items: _batch,
                  active: _batchActive,
                  onCancel: _cancelBatch,
                  onDismiss: () => _update(() => _batch = const []),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              _SectionTitle(
                title: 'Nearby devices',
                trailing: _scanning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              if (peers.isEmpty)
                _NoDevices(searching: !_firstScanDone, error: _scanError)
              else
                for (final peer in peers)
                  Padding(
                    key: ValueKey(peer.id),
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _PeerTile(
                      alias: _alias(peer),
                      address: peer.address.address,
                      action: _selected.isEmpty
                          ? 'Choose songs'
                          : 'Send ${_selected.length}',
                      enabled: !_batchActive,
                      onTap: () => unawaited(_sendTo(peer)),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: AppType.title),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon, this.color});

  final PhosphorIconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: AppRadii.all(AppRadii.md),
      ),
      child: Center(child: PhosphorIcon(icon, size: 20, color: tint)),
    );
  }
}

class _VisibilityCard extends StatelessWidget {
  const _VisibilityCard({
    required this.alias,
    required this.error,
    required this.incoming,
    required this.received,
    required this.receivedCount,
  });

  final String? alias;
  final String? error;
  final NearbyOffer? incoming;
  final int received;
  final int receivedCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final title = error != null
        ? 'Not visible'
        : alias == null
        ? 'Getting ready…'
        : 'Visible as “$alias”';
    final subtitle =
        error ??
        'Other Monolith devices on this Wi-Fi can send to you while this '
            'screen is open. You approve every song.';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _IconBadge(
                icon: error != null
                    ? PhosphorIcons.wifiSlash()
                    : PhosphorIcons.broadcast(),
                color: error != null ? scheme.error : null,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: AppType.label,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (incoming != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'Receiving “${incoming!.title}”',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyMedium?.copyWith(fontWeight: AppType.label),
            ),
            const SizedBox(height: AppSpacing.xs),
            _Progress(value: received, total: incoming!.size),
          ],
          if (receivedCount > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                PhosphorIcon(
                  PhosphorIcons.checkCircle(),
                  size: 16,
                  color: scheme.primary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  '$receivedCount ${receivedCount == 1 ? 'song' : 'songs'} '
                  'received',
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: AppType.label,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.value, required this.total});

  final int value;
  final int total;

  static String megabytes(int bytes) =>
      '${(bytes / 1000000).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RepaintBoundary(
          child: LinearProgressIndicator(
            value: total > 0 && value > 0 ? value / total : null,
            minHeight: 4,
            borderRadius: AppRadii.all(AppRadii.pill),
            backgroundColor: scheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '${megabytes(value)} of ${megabytes(total)}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _SelectedSongs extends StatelessWidget {
  const _SelectedSongs({
    required this.tracks,
    required this.onPick,
    required this.onRemove,
  });

  final List<Track> tracks;
  final VoidCallback? onPick;
  final void Function(Track track)? onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    if (tracks.isEmpty) {
      return AppCard(
        onTap: onPick,
        child: Row(
          children: [
            _IconBadge(icon: PhosphorIcons.musicNotesPlus()),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                'Choose songs, then tap a device below. Cover art is sent '
                'with each song.',
                style: textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        children: [
          for (final track in tracks)
            ListTile(
              key: ValueKey(track.id),
              leading: SizedBox.square(
                dimension: 44,
                child: TrackArtwork(
                  track: track,
                  borderRadius: AppRadii.all(AppRadii.sm),
                ),
              ),
              title: Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: onRemove == null
                  ? null
                  : IconButton(
                      tooltip: 'Remove ${track.title}',
                      onPressed: () => onRemove!(track),
                      icon: PhosphorIcon(AppIcons.close, size: 18),
                    ),
            ),
        ],
      ),
    );
  }
}

class _PeerTile extends StatelessWidget {
  const _PeerTile({
    required this.alias,
    required this.address,
    required this.action,
    required this.enabled,
    required this.onTap,
  });

  final String alias;
  final String address;
  final String action;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      enabled: enabled,
      label: '$action to $alias',
      onTap: enabled ? onTap : null,
      excludeSemantics: true,
      child: AppCard(
        onTap: enabled ? onTap : null,
        child: Row(
          children: [
            _IconBadge(icon: PhosphorIcons.devices()),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    alias,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: AppType.label,
                    ),
                  ),
                  Text(
                    address,
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Opacity(
              opacity: enabled ? 1 : 0.4,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: AppRadii.all(AppRadii.pill),
                ),
                child: Text(
                  action,
                  style: textTheme.labelLarge?.copyWith(
                    color: scheme.onPrimary,
                    fontWeight: AppType.label,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoDevices extends StatelessWidget {
  const _NoDevices({required this.searching, required this.error});

  final bool searching;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    if (searching) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Text(
          'Looking for Monolith devices…',
          style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
      );
    }
    final tips = [
      'Open Share on the other device too — phones: Library → share icon; '
          'desktop: the Share button.',
      'Both devices must be on the same Wi-Fi. Guest networks and hotspots '
          'with "client isolation" hide devices from each other.',
      'Windows: allow Monolith through Windows Defender Firewall on Private '
          'networks, and set the Wi-Fi network profile to Private.',
      'iPhone/iPad: Settings → Privacy & Security → Local Network → '
          'turn on Monolith.',
    ];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No devices yet',
            style: textTheme.titleSmall?.copyWith(fontWeight: AppType.label),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            error ?? 'Still searching. If nothing shows up:',
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final tip in tips)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: PhosphorIcon(
                      PhosphorIcons.info(),
                      size: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      tip,
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _BatchCard extends StatelessWidget {
  const _BatchCard({
    required this.peerName,
    required this.items,
    required this.active,
    required this.onCancel,
    required this.onDismiss,
  });

  final String peerName;
  final List<_BatchItem> items;
  final bool active;
  final VoidCallback onCancel;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final done = items.where((i) => i.state == _ItemState.done).length;
    final heading = active
        ? 'Sending to $peerName · $done of ${items.length}'
        : done == items.length
        ? 'Sent ${items.length} to $peerName'
        : 'Sent $done of ${items.length} to $peerName';

    return AppCard(
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  heading,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: AppType.label,
                  ),
                ),
              ),
              if (active)
                TextButton(onPressed: onCancel, child: const Text('Cancel'))
              else
                IconButton(
                  tooltip: 'Clear',
                  onPressed: onDismiss,
                  icon: PhosphorIcon(AppIcons.close, size: 18),
                ),
            ],
          ),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _StateIcon(state: item.state),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          item.track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodyMedium,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        _label(item),
                        style: textTheme.bodySmall?.copyWith(
                          color: item.state == _ItemState.failed
                              ? scheme.error
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  if (item.state == _ItemState.sending) ...[
                    const SizedBox(height: AppSpacing.xs),
                    _Progress(value: item.sent, total: item.total),
                  ],
                  if (item.error != null && item.state == _ItemState.failed)
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 26,
                        top: AppSpacing.xs,
                      ),
                      child: Text(
                        item.error!,
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _label(_BatchItem item) => switch (item.state) {
    _ItemState.queued => 'Queued',
    _ItemState.connecting => 'Connecting…',
    _ItemState.waiting => 'Waiting for OK…',
    _ItemState.sending => 'Sending',
    _ItemState.done => 'Sent',
    _ItemState.declined => 'Declined',
    _ItemState.failed => 'Not sent',
  };
}

class _StateIcon extends StatelessWidget {
  const _StateIcon({required this.state});

  final _ItemState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (state) {
      _ItemState.done => PhosphorIcon(
        PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
        size: 18,
        color: scheme.primary,
      ),
      _ItemState.declined => PhosphorIcon(
        PhosphorIcons.prohibit(),
        size: 18,
        color: scheme.onSurfaceVariant,
      ),
      _ItemState.failed => PhosphorIcon(
        PhosphorIcons.warningCircle(),
        size: 18,
        color: scheme.error,
      ),
      _ItemState.queued => PhosphorIcon(
        PhosphorIcons.clock(),
        size: 18,
        color: scheme.onSurfaceVariant,
      ),
      _ => const SizedBox.square(
        dimension: 18,
        child: Padding(
          padding: EdgeInsets.all(2),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    };
  }
}

/// Multi-select song picker with search and thumbnails. Returns the chosen
/// tracks in library order, or null when dismissed.
class _SongPicker extends StatefulWidget {
  const _SongPicker({required this.tracks, required this.initial});

  final List<Track> tracks;
  final List<Track> initial;

  @override
  State<_SongPicker> createState() => _SongPickerState();
}

class _SongPickerState extends State<_SongPicker> {
  late final Set<String> _chosen = {for (final t in widget.initial) t.id};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final query = _query.trim().toLowerCase();
    final visible = query.isEmpty
        ? widget.tracks
        : widget.tracks
              .where(
                (t) =>
                    t.title.toLowerCase().contains(query) ||
                    t.artist.toLowerCase().contains(query),
              )
              .toList();

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.85,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenInset,
              0,
              AppSpacing.screenInset,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Choose songs',
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: AppType.title,
                    ),
                  ),
                ),
                if (_chosen.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(_chosen.clear),
                    child: const Text('Clear'),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenInset,
            ),
            child: TextField(
              onChanged: (value) => setState(() => _query = value),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search songs or artists',
                prefixIcon: PhosphorIcon(PhosphorIcons.magnifyingGlass()),
                border: OutlineInputBorder(
                  borderRadius: AppRadii.all(AppRadii.md),
                ),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: widget.tracks.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Text(
                        'No songs stored on this device yet. Import or '
                        'download music first.',
                        textAlign: TextAlign.center,
                        style: textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final track = visible[index];
                      final chosen = _chosen.contains(track.id);
                      return CheckboxListTile(
                        key: ValueKey(track.id),
                        value: chosen,
                        onChanged: (_) => setState(() {
                          if (!_chosen.remove(track.id)) _chosen.add(track.id);
                        }),
                        secondary: SizedBox.square(
                          dimension: 44,
                          child: TrackArtwork(
                            track: track,
                            borderRadius: AppRadii.all(AppRadii.sm),
                          ),
                        ),
                        title: Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenInset,
              AppSpacing.sm,
              AppSpacing.screenInset,
              AppSpacing.md,
            ),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  widget.tracks.where((t) => _chosen.contains(t.id)).toList(),
                ),
                child: Text(
                  _chosen.isEmpty
                      ? 'Done'
                      : 'Select ${_chosen.length} '
                            '${_chosen.length == 1 ? 'song' : 'songs'}',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Per-song consent with sender, title, file name, size and whether cover art
/// comes along. The 60-second countdown matches the desktop consent timeout;
/// expiry is a decline.
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
    final textTheme = Theme.of(context).textTheme;
    final offer = widget.offer;
    return AlertDialog(
      icon: PhosphorIcon(PhosphorIcons.musicNote(), color: scheme.primary),
      title: const Text('Accept song?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            offer.title,
            style: textTheme.titleMedium?.copyWith(fontWeight: AppType.title),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${offer.name} • ${_Progress.megabytes(offer.size)}'
            '${offer.hasArtwork ? ' • with cover art' : ''}\n'
            'from ${widget.sender}',
            style: textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Declining automatically in $_secondsLeft s',
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
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
