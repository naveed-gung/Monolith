import 'dart:io';

import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../models/music_models.dart';
import 'artwork_painters.dart';

class TrackArtwork extends StatelessWidget {
  const TrackArtwork({
    super.key,
    required this.track,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
  });

  final Track track;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(borderRadius: borderRadius, child: _buildArtwork());
  }

  Widget _buildArtwork() {
    if (track.artworkFilePath != null) {
      final artworkFile = File(track.artworkFilePath!);
      if (artworkFile.existsSync()) {
        return Image.file(
          artworkFile,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallbackArtwork(),
        );
      }
    }

    if (track.artworkQueryId != null) {
      return QueryArtworkWidget(
        id: track.artworkQueryId!,
        type: ArtworkType.AUDIO,
        artworkBorder: BorderRadius.zero,
        artworkFit: BoxFit.cover,
        nullArtworkWidget: _fallbackArtwork(),
      );
    }

    if (track.artworkUrl != null && track.artworkUrl!.isNotEmpty) {
      return Image.network(
        track.artworkUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallbackArtwork(),
      );
    }

    return _fallbackArtwork();
  }

  Widget _fallbackArtwork() {
    return CustomPaint(
      painter: AlbumArtPainter(colors: track.colors),
      child: const SizedBox.expand(),
    );
  }
}
