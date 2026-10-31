/// Represents a single track pulled from YouTube.
class Track {
  final String videoId;
  final String title;
  final String author;
  final String thumbnailUrl;
  final Duration duration;

  Track({
    required this.videoId,
    required this.title,
    required this.author,
    required this.thumbnailUrl,
    required this.duration,
  });

  Map<String, dynamic> toJson() => {
        'videoId': videoId,
        'title': title,
        'author': author,
        'thumbnailUrl': thumbnailUrl,
        'durationMs': duration.inMilliseconds,
      };

  factory Track.fromJson(Map<String, dynamic> json) => Track(
        videoId: json['videoId'] as String,
        title: json['title'] as String,
        author: json['author'] as String,
        thumbnailUrl: json['thumbnailUrl'] as String,
        duration: Duration(milliseconds: json['durationMs'] as int? ?? 0),
      );

  /// "3:07" style length, or empty when YouTube didn't give one.
  String get lengthLabel {
    if (duration == Duration.zero) return '';
    final m = duration.inMinutes;
    final s = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
