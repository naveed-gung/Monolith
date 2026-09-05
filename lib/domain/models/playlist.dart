import 'package:collection/collection.dart';

/// An ordered, user-curated list of track ids.
///
/// Pure Dart and immutable. `trackIds` is stored as-is; treat it as
/// read-only — mutate through [copyWith] with a fresh list instead.
class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    List<String>? trackIds,
    required this.createdAt,
  }) : trackIds = trackIds ?? const [];

  final String id;
  final String name;

  /// Ordered references into the library; positions matter for playback.
  final List<String> trackIds;
  final DateTime createdAt;

  Playlist copyWith({
    String? id,
    String? name,
    List<String>? trackIds,
    DateTime? createdAt,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      trackIds: trackIds ?? this.trackIds,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  static const _trackIdEquality = ListEquality<String>();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Playlist &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          _trackIdEquality.equals(trackIds, other.trackIds) &&
          createdAt == other.createdAt;

  @override
  int get hashCode =>
      Object.hash(id, name, _trackIdEquality.hash(trackIds), createdAt);

  @override
  String toString() => 'Playlist($id, $name, ${trackIds.length} tracks)';
}
