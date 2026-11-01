import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/track.dart';

/// Web version: browsers can't use youtube_explode (YouTube blocks it), so
/// search goes through the official YouTube Data API with the user's own
/// free key. The key is kept in this browser only.
class YoutubeKey extends ChangeNotifier {
  static const _prefKey = 'youtubeApiKey';

  /// Set at build time with --dart-define=YT_KEY=... (optional).
  static const _builtIn = String.fromEnvironment('YT_KEY');

  static String current = _builtIn;

  bool get hasKey => current.isNotEmpty;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    if (saved != null && saved.isNotEmpty) current = saved;
  }

  /// Checks the key with one cheap request, then saves it.
  Future<void> save(String key) async {
    key = key.trim();
    final res = await http.get(Uri.https('www.googleapis.com',
        '/youtube/v3/videos', {'part': 'id', 'id': 'dQw4w9WgXcQ', 'key': key}));
    if (res.statusCode != 200) throw Exception(_apiError(res));
    current = key;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, key);
    notifyListeners();
  }

  Future<void> clear() async {
    current = _builtIn;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
    notifyListeners();
  }
}

String _apiError(http.Response res) {
  try {
    final err = (jsonDecode(res.body) as Map)['error'] as Map;
    final reason = ((err['errors'] as List?)?.firstOrNull as Map?)?['reason'];
    if (reason == 'quotaExceeded') {
      return 'Today\'s YouTube search limit is used up. It resets at midnight '
          'Pacific time.';
    }
    if (res.statusCode == 400 || res.statusCode == 403) {
      return 'YouTube refused the key: ${err['message']}';
    }
    return '${err['message']}';
  } catch (_) {
    return 'YouTube search failed (${res.statusCode})';
  }
}

/// "PT4M13S" -> 4:13.
Duration _isoDuration(String s) {
  final m = RegExp(r'PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?').firstMatch(s);
  if (m == null) return Duration.zero;
  int g(int i) => int.tryParse(m.group(i) ?? '') ?? 0;
  return Duration(hours: g(1), minutes: g(2), seconds: g(3));
}

String _unescape(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>');

/// One search costs 101 of the key's 10,000 free daily units, so about
/// 100 searches a day.
Future<List<Track>> webYoutubeSearch(String query) async {
  final key = YoutubeKey.current;
  if (key.isEmpty) throw Exception('Add your YouTube key first');
  final res =
      await http.get(Uri.https('www.googleapis.com', '/youtube/v3/search', {
    'part': 'snippet',
    'type': 'video',
    'maxResults': '20',
    'q': query,
    'key': key,
  }));
  if (res.statusCode != 200) throw Exception(_apiError(res));
  final items = ((jsonDecode(res.body) as Map)['items'] as List).cast<Map>();
  final ids = [for (final i in items) (i['id'] as Map)['videoId'] as String];
  if (ids.isEmpty) return [];

  // Lengths (and whether the video may be embedded) come from a second call.
  final details =
      await http.get(Uri.https('www.googleapis.com', '/youtube/v3/videos', {
    'part': 'contentDetails,status',
    'id': ids.join(','),
    'key': key,
  }));
  final lengths = <String, Duration>{};
  final blocked = <String>{};
  if (details.statusCode == 200) {
    for (final v
        in ((jsonDecode(details.body) as Map)['items'] as List).cast<Map>()) {
      lengths[v['id'] as String] = _isoDuration(
          (v['contentDetails'] as Map?)?['duration'] as String? ?? '');
      if ((v['status'] as Map?)?['embeddable'] == false) {
        blocked.add(v['id'] as String);
      }
    }
  }
  return [
    for (final i in items)
      if (!blocked.contains((i['id'] as Map)['videoId']))
        Track(
          videoId: (i['id'] as Map)['videoId'] as String,
          title: _unescape((i['snippet'] as Map)['title'] as String),
          author: _unescape((i['snippet'] as Map)['channelTitle'] as String),
          thumbnailUrl:
              'https://i.ytimg.com/vi/${(i['id'] as Map)['videoId']}/mqdefault.jpg',
          duration: lengths[(i['id'] as Map)['videoId']] ?? Duration.zero,
        ),
  ];
}
