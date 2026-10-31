import 'dart:convert';
import 'package:dj_musi_app/models/track.dart';
import 'package:dj_musi_app/screens/karaoke_screen.dart';
import 'package:dj_musi_app/services/lyrics_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('parses LRC, including repeated timestamps', () {
    final l = parseLrc('[ar: Someone]\n[00:12.50] Hello\n'
        '[00:20.00][01:05.25] Chorus line\n[00:30.00]\n');
    expect(l.synced, isTrue);
    expect(l.lines.map((x) => x.text),
        ['Hello', 'Chorus line', '♪', 'Chorus line']);
    expect(l.lines.first.time, const Duration(milliseconds: 12500));
    expect(l.lines.last.time, const Duration(milliseconds: 65250));
    expect(l.indexAt(const Duration(seconds: 5)), -1);
    expect(l.indexAt(const Duration(seconds: 21)), 1);
    expect(l.indexAt(const Duration(minutes: 3)), 3);
  });

  test('cleans YouTube titles for lyric search', () {
    expect(cleanTitleForLyrics('Adele - Hello (Official Music Video) [HD]'),
        'Adele Hello');
    expect(cleanTitleForLyrics('Drake - One Dance ft. Wizkid & Kyla'),
        'Drake One Dance');
    expect(cleanTitleForLyrics('Burna Boy | Last Last (Lyrics)'),
        'Burna Boy Last Last');
  });

  test('karaoke query adds the word once', () {
    expect(karaokeQuery('hello adele'), 'hello adele karaoke');
    expect(karaokeQuery('Hello Karaoke version'), 'Hello Karaoke version');
  });

  test('find() asks LRCLIB and prefers synced lyrics of matching length',
      () async {
    late Uri asked;
    final client = MockClient((req) async {
      asked = req.url;
      expect(req.headers['User-Agent'], contains('DJMusi'));
      return http.Response(
          jsonEncode([
            {'duration': 100, 'syncedLyrics': '[00:01.00] wrong length'},
            {'duration': 295, 'syncedLyrics': '[00:01.00] right one'},
            {'duration': 295, 'plainLyrics': 'plain'},
          ]),
          200);
    });
    final lyrics = await LyricsService(client).find(Track(
        videoId: 'v',
        title: 'Adele - Hello (Official Music Video)',
        author: 'Adele',
        thumbnailUrl: '',
        duration: const Duration(seconds: 297)));
    expect(asked.host, 'lrclib.net');
    expect(asked.path, '/api/search');
    expect(asked.queryParameters['q'], 'Adele Hello');
    expect(lyrics!.lines.single.text, 'right one');
  });

  test('falls back to plain lyrics', () {
    final l = LyricsService.pickBest([
      {'duration': 200, 'plainLyrics': 'a\nb'}
    ], const Duration(seconds: 200));
    expect(l!.synced, isFalse);
    expect(l.lines.length, 2);
  });
}
