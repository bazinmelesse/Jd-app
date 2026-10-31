import 'package:dj_musi_app/models/track.dart';
import 'package:dj_musi_app/services/library_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Track t(String id) => Track(
    videoId: id,
    title: 'Song $id',
    author: 'A',
    thumbnailUrl: 'x',
    duration: const Duration(seconds: 200));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('playlists and history survive a restart', () async {
    final lib = LibraryController();
    await lib.load();
    final p = lib.createPlaylist('Party');
    expect(lib.addToPlaylist(p, t('a')), isTrue);
    expect(lib.addToPlaylist(p, t('a')), isFalse);
    lib.addToPlaylist(p, t('b'));
    lib.addToPlaylist(p, t('c'));
    lib.reorderPlaylist(p, 0, 2);
    for (var i = 0; i < 12; i++) {
      lib.addSearch('q$i');
    }
    lib.addSearch('Q3');
    lib.addRecentTrack(t('z'));

    final again = LibraryController();
    await again.load();
    expect(again.playlists.single.name, 'Party');
    expect(again.playlists.single.tracks.map((x) => x.videoId), ['b', 'c', 'a']);
    expect(again.recentSearches.first, 'Q3');
    expect(again.recentSearches.length, LibraryController.maxRecentSearches);
    expect(again.recentSearches.where((s) => s.toLowerCase() == 'q3').length, 1);
    expect(again.recentTracks.single.duration, const Duration(seconds: 200));
  });
}
