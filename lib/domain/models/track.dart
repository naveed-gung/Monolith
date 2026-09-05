/// Immutable library track — the central domain model of Monolith 2.0.
///
/// Pure Dart (no Flutter imports). Plain immutable class instead of freezed:
/// hand-written `copyWith`/equality/JSON keeps the build free of codegen and
/// the model easy to reason about.
library;

/// Where a track came from.
enum TrackSource { downloaded, imported, device }

class Track {
  const Track({
    required this.id,
    required this.title,
    this.artist = 'Unknown',
    this.album = '',
    this.genre = '',
    this.durationMs = 0,
    required this.filePath,
    this.artworkPath,
    this.artworkUrl,
    this.source = TrackSource.downloaded,
    required this.addedAt,
    this.playCount = 0,
    this.lastPlayedAt,
  });

  /// Stable unique identifier. Entries recovered from disk derive theirs from
  /// a path hash (see [LibraryStore]) so repeated rescans never duplicate.
  final String id;
  final String title;
  final String artist;
  final String album;
  final String genre;

  /// Duration in milliseconds (0 = unknown).
  final int durationMs;

  /// Absolute path of the audio file. Empty means "no playable file";
  /// such entries are pruned when the library loads.
  final String filePath;

  /// Local sidecar artwork path, if any.
  final String? artworkPath;

  /// Remote artwork URL, if any.
  final String? artworkUrl;
  final TrackSource source;

  /// When the track entered the library (file mtime for disk-recovered ones).
  final DateTime addedAt;

  /// Smart-playlist metadata.
  final int playCount;
  final DateTime? lastPlayedAt;

  Track copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    String? genre,
    int? durationMs,
    String? filePath,
    String? artworkPath,
    String? artworkUrl,
    TrackSource? source,
    DateTime? addedAt,
    int? playCount,
    DateTime? lastPlayedAt,
  }) {
    return Track(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      genre: genre ?? this.genre,
      durationMs: durationMs ?? this.durationMs,
      filePath: filePath ?? this.filePath,
      artworkPath: artworkPath ?? this.artworkPath,
      artworkUrl: artworkUrl ?? this.artworkUrl,
      source: source ?? this.source,
      addedAt: addedAt ?? this.addedAt,
      playCount: playCount ?? this.playCount,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
    );
  }

  /// Stable v2 JSON keys. Dates serialize as ISO-8601 strings.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'genre': genre,
      'durationMs': durationMs,
      'filePath': filePath,
      'artworkPath': artworkPath,
      'artworkUrl': artworkUrl,
      'source': source.name,
      'addedAt': addedAt.toIso8601String(),
      'playCount': playCount,
      'lastPlayedAt': lastPlayedAt?.toIso8601String(),
    };
  }

  /// Tolerant parser: accepts v2 keys and, for migration, the legacy v1 keys
  /// (`artworkFilePath`, `addedAtMs`, `lastPlayedMs`, epoch-milli dates and
  /// the retired `mock` source).
  factory Track.fromJson(Map<String, dynamic> json) {
    return Track(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String? ?? 'Unknown',
      album: json['album'] as String? ?? '',
      genre: json['genre'] as String? ?? '',
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      filePath: json['filePath'] as String? ?? '',
      artworkPath: (json['artworkPath'] ?? json['artworkFilePath']) as String?,
      artworkUrl: json['artworkUrl'] as String?,
      source: _decodeSource(json['source'] as String?),
      addedAt:
          _parseDate(json['addedAt'] ?? json['addedAtMs']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      playCount: (json['playCount'] as num?)?.toInt() ?? 0,
      lastPlayedAt: _parseDate(json['lastPlayedAt'] ?? json['lastPlayedMs']),
    );
  }

  static TrackSource _decodeSource(String? name) {
    if (name == 'device') return TrackSource.device;
    if (name == 'imported') return TrackSource.imported;
    // 'downloaded', unknown names and the retired v1 'mock' all land here;
    // entries whose file is gone are pruned on load anyway.
    return TrackSource.downloaded;
  }

  static DateTime? _parseDate(Object? value) {
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Track &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title &&
          artist == other.artist &&
          album == other.album &&
          genre == other.genre &&
          durationMs == other.durationMs &&
          filePath == other.filePath &&
          artworkPath == other.artworkPath &&
          artworkUrl == other.artworkUrl &&
          source == other.source &&
          addedAt == other.addedAt &&
          playCount == other.playCount &&
          lastPlayedAt == other.lastPlayedAt;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    artist,
    album,
    genre,
    durationMs,
    filePath,
    artworkPath,
    artworkUrl,
    source,
    addedAt,
    playCount,
    lastPlayedAt,
  );

  @override
  String toString() => 'Track($id, $title)';
}
