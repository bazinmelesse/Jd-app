import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/track.dart';

/// One line of lyrics; [time] is null for plain (unsynced) lyrics.
class LyricLine {
  final Duration? time;
  final String text;
  const LyricLine(this.time, this.text);
}

class Lyrics {
  final List<LyricLine> lines;
  final bool synced;
  const Lyrics(this.lines, {required this.synced});

  /// Index of the line being sung at [position], or -1 before the first.
  int indexAt(Duration position) {
    if (!synced) return -1;
    var current = -1;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].time! <= position) {
        current = i;
      } else {
        break;
      }
    }
    return current;
  }
}

/// Parses LRC text ("[01:23.45] some words") into timed lines.
Lyrics parseLrc(String lrc) {
  final stamp = RegExp(r'\[(\d+):(\d+(?:\.\d+)?)\]');
  final lines = <LyricLine>[];
  for (final raw in const LineSplitter().convert(lrc)) {
    final stamps = stamp.allMatches(raw).toList();
    if (stamps.isEmpty) continue;
    final text = raw.substring(stamps.last.end).trim();
    // A line can carry several timestamps when it repeats (choruses).
    for (final m in stamps) {
      final minutes = int.parse(m.group(1)!);
      final seconds = double.parse(m.group(2)!);
      lines.add(LyricLine(
        Duration(milliseconds: ((minutes * 60 + seconds) * 1000).round()),
        text.isEmpty ? '♪' : text,
      ));
    }
  }
  lines.sort((a, b) => a.time!.compareTo(b.time!));
  return Lyrics(lines, synced: true);
}

/// Turns a YouTube title like "Adele - Hello (Official Music Video) [HD]"
/// into a lyrics search like "Adele Hello".
String cleanTitleForLyrics(String title) {
  var t = title
      .replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]|【[^】]*】'), ' ')
      .replaceAll(
          RegExp(
              r'\b(official|music|video|audio|lyrics?|lyric video|hd|hq|4k|'
              r'visualizer|remastered|explicit|clean)\b',
              caseSensitive: false),
          ' ')
      .replaceAll(RegExp(r'\b(ft|feat)\.?\s.*$', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'[|"“”]'), ' ')
      .replaceAll(' - ', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return t;
}

/// Looks up lyrics on LRCLIB (free, no account needed), preferring
/// time-synced lyrics whose length matches the video.
class LyricsService {
  final http.Client _client;
  LyricsService([http.Client? client]) : _client = client ?? http.Client();

  Future<Lyrics?> find(Track track) async {
    final query = cleanTitleForLyrics(track.title);
    if (query.isEmpty) return null;
    final uri = Uri.https('lrclib.net', '/api/search', {'q': query});
    final response = await _client.get(uri, headers: {
      'User-Agent': 'DJMusi/0.9 (personal, non-commercial)',
    }).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return null;
    final results = (jsonDecode(response.body) as List)
        .cast<Map<String, dynamic>>()
        .where((r) => r['instrumental'] != true)
        .toList();
    if (results.isEmpty) return null;
    return pickBest(results, track.duration);
  }

  /// Synced lyrics within 10 s of the video's length win; then any synced;
  /// then plain lyrics.
  static Lyrics? pickBest(
      List<Map<String, dynamic>> results, Duration videoLength) {
    bool closeInLength(Map<String, dynamic> r) {
      final seconds = (r['duration'] as num?)?.toDouble();
      if (seconds == null || videoLength == Duration.zero) return false;
      return (seconds - videoLength.inSeconds).abs() <= 10;
    }

    String? synced(Map<String, dynamic> r) {
      final s = r['syncedLyrics'] as String?;
      return (s == null || s.trim().isEmpty) ? null : s;
    }

    for (final r in results) {
      if (closeInLength(r) && synced(r) != null) return parseLrc(synced(r)!);
    }
    for (final r in results) {
      if (synced(r) != null) return parseLrc(synced(r)!);
    }
    for (final r in results) {
      final plain = r['plainLyrics'] as String?;
      if (plain != null && plain.trim().isNotEmpty) {
        return Lyrics(
          const LineSplitter()
              .convert(plain)
              .map((l) => LyricLine(null, l))
              .toList(),
          synced: false,
        );
      }
    }
    return null;
  }
}
