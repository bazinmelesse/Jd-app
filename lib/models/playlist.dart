import 'track.dart';

/// A named, ordered list of tracks the user put together.
class Playlist {
  final String id;
  String name;
  final List<Track> tracks;

  Playlist({required this.id, required this.name, List<Track>? tracks})
      : tracks = tracks ?? [];

  /// Thumbnail of the first song, used as the playlist's cover.
  String? get coverUrl => tracks.isEmpty ? null : tracks.first.thumbnailUrl;

  Duration get totalLength =>
      tracks.fold(Duration.zero, (sum, t) => sum + t.duration);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'tracks': tracks.map((t) => t.toJson()).toList(),
      };

  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
        id: json['id'] as String,
        name: json['name'] as String,
        tracks: (json['tracks'] as List)
            .map((t) => Track.fromJson(t as Map<String, dynamic>))
            .toList(),
      );
}
