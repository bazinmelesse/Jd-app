import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import '../models/track.dart';
import 'engine/engine_bridge.dart';
import 'engine/local_song.dart';
import 'library_service.dart';
import 'youtube_service.dart';

enum PlayRepeat { off, all, one }

/// The music player used by the Stream, Karaoke and Library tabs. It lives
/// above the screens, so music keeps playing while you search, and the
/// mini player and full player both show the same song and queue.
class PlayerController extends ChangeNotifier {
  final YoutubeService youtube;
  final LibraryController library;

  PlayerController({required this.youtube, required this.library});

  /// The songs to play through, in order, and which one is playing.
  final List<Track> queue = [];
  int index = -1;

  /// Songs autoplay added (shown as "Suggested" in the queue).
  final Set<String> suggested = {};

  VideoPlayerController? video;
  String? error;
  bool get loading => current != null && video == null && error == null;

  PlayRepeat repeat = PlayRepeat.off;
  bool shuffle = false;

  /// When the queue runs out, keep going with songs picked from what you
  /// play and search for.
  bool autoplay = true;
  bool findingSuggestions = false;

  double volume = 1.0;
  bool muted = false;

  /// Whether the full player should show lyrics for the current song
  /// (karaoke videos already have them on screen).
  bool lyricsWanted = true;

  int _loadToken = 0;
  bool _advancing = false;
  final _random = Random();

  Track? get current =>
      index >= 0 && index < queue.length ? queue[index] : null;
  bool get isPlaying => video?.value.isPlaying ?? false;
  bool get hasNext =>
      index < queue.length - 1 ||
      (shuffle && queue.length > 1) ||
      repeat == PlayRepeat.all ||
      autoplay;
  List<Track> get upNext =>
      index + 1 < queue.length ? queue.sublist(index + 1) : const [];

  // ---- Changing what plays ----

  /// Replaces the queue with [songs] and plays [start].
  void playQueue(List<Track> songs, int start, {bool lyrics = true}) {
    queue
      ..clear()
      ..addAll(songs);
    suggested.clear();
    lyricsWanted = lyrics;
    _goTo(start);
  }

  /// Plays [track] right away; what was queued after the current song
  /// stays queued after it.
  void playNow(Track track, {bool lyrics = true}) {
    lyricsWanted = lyrics;
    if (current == null) {
      queue
        ..clear()
        ..add(track);
      _goTo(0);
      return;
    }
    queue.insert(index + 1, track);
    _goTo(index + 1);
  }

  /// Puts [track] right after the current song.
  void playNext(Track track) {
    if (current == null) return playNow(track);
    queue.insert(index + 1, track);
    suggested.remove(track.videoId);
    notifyListeners();
  }

  /// Adds [track] to the end of the queue (before any suggestions).
  void addToQueue(Track track) {
    if (current == null) return playNow(track);
    var at = queue.length;
    while (at > index + 1 && suggested.contains(queue[at - 1].videoId)) {
      at--;
    }
    queue.insert(at, track);
    notifyListeners();
  }

  void removeAt(int i) {
    if (i == index || i < 0 || i >= queue.length) return;
    queue.removeAt(i);
    if (i < index) index--;
    notifyListeners();
  }

  /// Moves a queued song (for drag-to-reorder in the queue list).
  void move(int from, int to) {
    if (from == index || to <= index) return;
    final t = queue.removeAt(from);
    queue.insert(to.clamp(index + 1, queue.length), t);
    notifyListeners();
  }

  void jumpTo(int i) {
    if (i >= 0 && i < queue.length) _goTo(i);
  }

  Future<void> _goTo(int i) async {
    final token = ++_loadToken;
    index = i;
    error = null;
    final old = video;
    video = null;
    notifyListeners();
    old?.removeListener(_onTick);
    await old?.dispose();
    final track = queue[i];
    if (!track.isLocal) library.addRecentTrack(track);
    try {
      final url = track.isLocal
          ? localSongUrl(track.localId)
          : isWebEngine
              // Plays in YouTube's own player (web/yt_player.js).
              ? 'ytembed:${track.videoId}?d=${track.duration.inMilliseconds}'
              : await youtube.getMuxedStreamUrl(track.videoId);
      final c = VideoPlayerController.networkUrl(Uri.parse(url));
      await c.initialize();
      if (token != _loadToken) {
        await c.dispose();
        return;
      }
      await c.setVolume(muted ? 0 : volume);
      c.addListener(_onTick);
      _advancing = false;
      video = c;
      notifyListeners();
      await c.play();
    } catch (e) {
      if (token == _loadToken) {
        error = 'Could not load this video: $e';
        notifyListeners();
      }
    }
    if (index == queue.length - 1) _topUp();
  }

  /// Moves on when a song ends: repeat it, play the next one, or stop.
  void _onTick() {
    final c = video;
    if (c == null) return;
    if (_advancing) {
      if (c.value.isPlaying) _advancing = false;
      return;
    }
    final v = c.value;
    if (v.isPlaying) return;
    final ended = v.duration > Duration.zero &&
        v.position >= v.duration - const Duration(milliseconds: 300);
    if (!ended) return;
    _advancing = true;
    notifyListeners();
    if (repeat == PlayRepeat.one) {
      c.seekTo(Duration.zero).then((_) {
        c.play();
        _advancing = false;
      });
    } else if (hasNext) {
      next();
    }
  }

  Future<void> next() async {
    if (queue.isEmpty) return;
    if (shuffle && upNext.isNotEmpty) {
      // Pick any later song and bring it forward.
      final pick = index + 1 + _random.nextInt(queue.length - index - 1);
      queue.insert(index + 1, queue.removeAt(pick));
      return _goTo(index + 1);
    }
    if (index < queue.length - 1) return _goTo(index + 1);
    if (autoplay) {
      await _topUp();
      if (index < queue.length - 1) return _goTo(index + 1);
    }
    if (repeat == PlayRepeat.all) return _goTo(0);
  }

  /// Like music apps: restarts the song unless it just began, then goes
  /// back one.
  void previous() {
    final c = video;
    if (c != null && c.value.position > const Duration(seconds: 3) ||
        index <= 0) {
      c?.seekTo(Duration.zero);
      return;
    }
    _goTo(index - 1);
  }

  /// Plays or pauses; starts over if the song had finished.
  Future<void> togglePlay() async {
    final c = video;
    if (c == null) return;
    if (c.value.isPlaying) {
      await c.pause();
    } else {
      final v = c.value;
      if (v.duration > Duration.zero &&
          v.position >= v.duration - const Duration(milliseconds: 300)) {
        await c.seekTo(Duration.zero);
      }
      await c.play();
    }
    notifyListeners();
  }

  Future<void> pause() async {
    await video?.pause();
    notifyListeners();
  }

  void seek(Duration to) => video?.seekTo(to);

  void skip(int seconds) {
    final c = video;
    if (c == null) return;
    var to = c.value.position + Duration(seconds: seconds);
    if (to < Duration.zero) to = Duration.zero;
    if (to > c.value.duration) to = c.value.duration;
    c.seekTo(to);
  }

  void setVolume(double v) {
    volume = v;
    muted = v == 0;
    video?.setVolume(v);
    notifyListeners();
  }

  void toggleMute() {
    muted = !muted;
    if (!muted && volume == 0) volume = 0.5;
    video?.setVolume(muted ? 0 : volume);
    notifyListeners();
  }

  void cycleRepeat() {
    repeat = PlayRepeat.values[(repeat.index + 1) % PlayRepeat.values.length];
    notifyListeners();
  }

  void toggleShuffle() {
    shuffle = !shuffle;
    notifyListeners();
  }

  void setAutoplay(bool on) {
    autoplay = on;
    notifyListeners();
    if (on && index == queue.length - 1) _topUp();
  }

  /// Stops and empties the player (the mini player's close button).
  Future<void> stop() async {
    _loadToken++;
    final old = video;
    video = null;
    queue.clear();
    suggested.clear();
    index = -1;
    error = null;
    notifyListeners();
    old?.removeListener(_onTick);
    await old?.dispose();
  }

  // ---- Autoplay suggestions ----

  Future<void>? _toppingUp;

  /// Adds a few suggested songs after the last one, if autoplay is on.
  Future<void> _topUp() {
    // Suggestions come from YouTube, so none for songs from the device.
    if (queue.isNotEmpty && queue.last.isLocal) return Future.value();
    if (!autoplay || current == null) return Future.value();
    return _toppingUp ??= _addSuggestions().whenComplete(() {
      _toppingUp = null;
    });
  }

  Future<void> _addSuggestions() async {
    findingSuggestions = true;
    notifyListeners();
    try {
      final picks = await suggestFor(
        current!,
        youtube: youtube,
        library: library,
        exclude: {for (final t in queue) t.videoId},
        random: _random,
      );
      for (final t in picks) {
        suggested.add(t.videoId);
        queue.add(t);
      }
    } catch (_) {
      // Offline or YouTube changed: just stop at the end of the queue.
    } finally {
      findingSuggestions = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _loadToken++;
    video?.dispose();
    super.dispose();
  }
}

/// Picks about five songs to play after [seed], from what you listen to:
/// YouTube's "up next" for the current song, plus songs by artists you
/// played recently and things you searched for. Skips songs you heard
/// lately and anything that isn't song-length.
Future<List<Track>> suggestFor(
  Track seed, {
  required YoutubeService youtube,
  required LibraryController library,
  required Set<String> exclude,
  required Random random,
  int count = 5,
}) async {
  final heardLately = {
    ...exclude,
    for (final t in library.recentTracks.take(30)) t.videoId,
  };
  bool songLength(Track t) =>
      t.duration == Duration.zero ||
      (t.duration >= const Duration(seconds: 90) &&
          t.duration <= const Duration(minutes: 12));
  bool fresh(Track t) => !heardLately.contains(t.videoId) && songLength(t);

  final pools = <List<Track>>[];
  try {
    pools.add((await youtube.related(seed.videoId)).where(fresh).toList());
  } catch (_) {}

  // Something from your own history: an artist you played or a search.
  final activity = <String>[
    for (final t in library.recentTracks.take(10))
      if (t.author.isNotEmpty) t.author,
    ...library.recentSearches.take(5),
    for (final p in library.playlists)
      for (final t in p.tracks.take(3))
        if (t.author.isNotEmpty) t.author,
  ];
  if (activity.isNotEmpty) {
    final query = activity[random.nextInt(activity.length)];
    try {
      pools.add(
          (await youtube.search(query)).where(fresh).toList()..shuffle(random));
    } catch (_) {}
  }

  // Take from the pools in turn so the mix varies: 3 related, 2 activity.
  final picks = <Track>[];
  final seen = <String>{};
  var round = 0;
  while (picks.length < count && pools.any((p) => p.isNotEmpty)) {
    final pool = pools[round % pools.length];
    round++;
    if (pool.isEmpty) continue;
    final t = pool.removeAt(0);
    // Avoid two versions of the same song.
    final key =
        t.title.toLowerCase().replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '').trim();
    if (seen.add(t.videoId) && seen.add(key)) picks.add(t);
  }
  return picks;
}
