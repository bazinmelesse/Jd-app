import '../../models/track.dart';

/// A song file the user opened from their own device (web version).
class LocalSong {
  final String id;
  final String name;
  const LocalSong(this.id, this.name);

  /// Tracks made from local files have ids that start with this.
  static const prefix = 'local:';

  /// "Artist - Title.mp3" becomes title "Title", artist "Artist".
  Track toTrack() {
    var base = name.replaceAll(RegExp(r'\.[A-Za-z0-9]{2,5}$'), '');
    var author = 'On this device';
    final dash = base.indexOf(' - ');
    if (dash > 0) {
      author = base.substring(0, dash).trim();
      base = base.substring(dash + 3).trim();
    }
    return Track(
        videoId: '$prefix$id',
        title: base,
        author: author,
        thumbnailUrl: '',
        duration: Duration.zero);
  }
}

extension LocalTrack on Track {
  /// True for a song opened from the device rather than YouTube.
  bool get isLocal => videoId.startsWith(LocalSong.prefix);
  String get localId => videoId.substring(LocalSong.prefix.length);
}
