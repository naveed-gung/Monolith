import 'package:flutter/material.dart';

import '../models/music_models.dart';

class DemoCatalog {
  static final fallbackTracks = [
    Track(
      id: 'mock-monolith-signal',
      title: 'Monolith Signal',
      artist: 'Device Library',
      album: 'Mock Album',
      genre: 'Placeholder audio',
      duration: Duration(minutes: 3, seconds: 18),
      colors: [Color(0xFF5CE1D8), Color(0xFF145DA0), Color(0xFF0C1B2A)],
      blurb:
          'Import songs from your device or use the downloader to replace this placeholder track.',
      source: TrackSource.mock,
    ),
  ];
}
