import 'dart:io';

/// One lyric line. [time] is null for plain (unsynced) lyrics.
class LyricLine {
  const LyricLine(this.time, this.text);
  final Duration? time;
  final String text;
}

/// Loads and parses lyrics for a track.
///
/// Source: a `.lrc` sidecar sitting next to the audio file (same name, `.lrc`
/// extension) — the de-facto standard for synced lyrics. Both timestamped
/// (`[mm:ss.xx] line`) and plain text files are supported.
class LyricsService {
  const LyricsService();

  static final RegExp _timeTag = RegExp(r'\[(\d+):(\d+)(?:[.:](\d+))?\]');

  Future<List<LyricLine>?> loadForAudio(String audioPath) async {
    final raw = await _readSidecar(audioPath);
    if (raw == null) return null;
    final lines = parse(raw);
    return lines.isEmpty ? null : lines;
  }

  Future<String?> _readSidecar(String audioPath) async {
    final dot = audioPath.lastIndexOf('.');
    final stem = dot == -1 ? audioPath : audioPath.substring(0, dot);
    final file = File('$stem.lrc');
    try {
      return await file.exists() ? await file.readAsString() : null;
    } catch (_) {
      return null;
    }
  }

  /// Parse `.lrc` content into ordered [LyricLine]s. Metadata tags such as
  /// `[ar:...]`/`[ti:...]` are skipped; lines with no timestamp are kept as
  /// plain (unsynced) text.
  List<LyricLine> parse(String raw) {
    final out = <LyricLine>[];
    for (final rawLine in raw.split('\n')) {
      final matches = _timeTag.allMatches(rawLine).toList();
      final text = rawLine.replaceAll(_timeTag, '').trim();
      if (matches.isEmpty) {
        if (text.isNotEmpty && !text.startsWith('[')) {
          out.add(LyricLine(null, text));
        }
        continue;
      }
      for (final m in matches) {
        final min = int.tryParse(m.group(1) ?? '') ?? 0;
        final sec = int.tryParse(m.group(2) ?? '') ?? 0;
        final frac = m.group(3);
        final ms = frac == null
            ? 0
            : int.tryParse(frac.padRight(3, '0').substring(0, 3)) ?? 0;
        out.add(
          LyricLine(
            Duration(minutes: min, seconds: sec, milliseconds: ms),
            text,
          ),
        );
      }
    }
    out.sort(
      (a, b) => (a.time ?? Duration.zero).compareTo(b.time ?? Duration.zero),
    );
    return out;
  }
}
