import 'dart:math';
import 'package:dj_musi_app/models/track.dart';
import 'package:dj_musi_app/services/library_service.dart';
import 'package:dj_musi_app/services/player_service.dart';
import 'package:dj_musi_app/services/youtube_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Track t(String id, {String author = 'A', int secs = 200}) => Track(
    videoId: id,
    title: 'Song $id',
    author: author,
    thumbnailUrl: 'x',
    duration: Duration(seconds: secs));

/// YouTube stand-in: canned "up next" and search results, and videos that
/// never load (so no real player is needed).
class FakeYoutube extends YoutubeService {
  final searches = <String>[];

  @override
  Future<List<Track>> related(String videoId) async => [
        t('r1'),
        t('heard'), // played lately: skipped
        t('long', secs: 3600), // an hour-long mix: skipped
        t('r2'),
        t('r3'),
        t('r4'),
      ];

  @override
  Future<List<Track>> search(String query) async {
    searches.add(query);
    return [t('s1', author: query), t('s2', author: query)];
  }

  @override
  Future<String> getMuxedStreamUrl(String videoId) async =>
      throw Exception('offline');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('autoplay picks fresh, song-length tracks from up next and history',
      () async {
    final lib = LibraryController();
    await lib.load();
    lib.addRecentTrack(t('heard', author: 'Teddy Afro'));
    final yt = FakeYoutube();
    final picks = await suggestFor(t('seed'),
        youtube: yt, library: lib, exclude: {'seed'}, random: Random(1));
    final ids = picks.map((p) => p.videoId).toList();
    expect(ids.length, 5);
    expect(ids, isNot(contains('heard')));
    expect(ids, isNot(contains('long')));
    expect(ids.where((i) => i.startsWith('s')), isNotEmpty,
        reason: 'mixes in songs from your own listening');
    expect(yt.searches.single, 'Teddy Afro');
  });

  test('queue: play next, add to queue, reorder, remove', () async {
    final lib = LibraryController();
    await lib.load();
    final p = PlayerController(youtube: FakeYoutube(), library: lib)
      ..autoplay = false;
    p.playQueue([t('a'), t('b')], 0);
    p.addToQueue(t('c'));
    p.playNext(t('n'));
    expect(p.queue.map((x) => x.videoId), ['a', 'n', 'b', 'c']);
    p.move(3, 1); // drag c up to right after the current song
    expect(p.queue.map((x) => x.videoId), ['a', 'c', 'n', 'b']);
    p.removeAt(2);
    expect(p.queue.map((x) => x.videoId), ['a', 'c', 'b']);
    p.playNow(t('z'));
    await Future<void>.delayed(Duration.zero);
    expect(p.current!.videoId, 'z');
    expect(p.upNext.map((x) => x.videoId), ['c', 'b'],
        reason: 'what was queued stays queued');
    expect(p.error, isNotNull, reason: 'the fake video never loads');
  });

  test('autoplay adds suggestions when the queue runs out', () async {
    final lib = LibraryController();
    await lib.load();
    final p = PlayerController(youtube: FakeYoutube(), library: lib);
    p.playQueue([t('only')], 0);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(p.upNext.length, 5);
    expect(p.upNext.every((x) => p.suggested.contains(x.videoId)), isTrue);
    p.addToQueue(t('mine'));
    expect(p.upNext.first.videoId, 'mine',
        reason: 'your own picks go before the suggestions');
  });
}
