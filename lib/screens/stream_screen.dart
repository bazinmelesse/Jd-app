import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/track.dart';
import '../services/player_service.dart';
import '../widgets/add_to_playlist.dart';
import '../widgets/mini_player.dart';
import '../widgets/track_search_panel.dart';
import 'video_player_screen.dart';
import 'device_music_screen.dart';
import '../services/engine/engine_bridge.dart';
import '../widgets/youtube_key_gate.dart';

/// Plays [track] full screen, with [queue] (the list it was picked from:
/// a playlist, karaoke results...) queued around it for next/previous.
void openTrackPlayer(BuildContext context, Track track,
    {List<Track>? queue, bool showLyrics = true}) {
  final songs = List<Track>.of(queue ?? [track]);
  var start = songs.indexWhere((t) => t.videoId == track.videoId);
  if (start < 0) {
    songs.insert(0, track);
    start = 0;
  }
  context.read<PlayerController>().playQueue(songs, start, lyrics: showLyrics);
  openFullPlayer(context);
}

/// The "Stream" tab - a Musi-style search screen that stays put while
/// music plays in the mini player below. Tap a result to play it now, or
/// use + to queue it up next.
class StreamScreen extends StatelessWidget {
  const StreamScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerController>();
    void say(String text) => ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
          SnackBar(content: Text(text), duration: const Duration(seconds: 2)));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stream'),
        actions: [
          if (isWebEngine)
            IconButton(
              tooltip: 'Songs on this device',
              icon: const Icon(Icons.folder_open),
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DeviceMusicScreen())),
            ),
          IconButton(
            tooltip: 'Queue',
            icon: const Icon(Icons.queue_music),
            onPressed: () => showQueueSheet(context),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: YoutubeKeyGate(
          child: TrackSearchPanel(
            hintText: 'Search videos or songs...',
            onTrackTap: (track, _) => player.playNow(track),
            trailingBuilder: (track) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Add to queue',
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () {
                    final playing = player.current != null;
                    player.addToQueue(track);
                    say(playing ? 'Added to the queue' : 'Playing now');
                  },
                ),
                PopupMenuButton<String>(
                  tooltip: 'More',
                  onSelected: (choice) {
                    switch (choice) {
                      case 'now':
                        player.playNow(track);
                      case 'next':
                        player.playNext(track);
                        say('Plays next');
                      case 'queue':
                        player.addToQueue(track);
                        say('Added to the queue');
                      case 'playlist':
                        showAddToPlaylistSheet(context, track);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'now', child: Text('Play now')),
                    PopupMenuItem(value: 'next', child: Text('Play next')),
                    PopupMenuItem(value: 'queue', child: Text('Add to queue')),
                    PopupMenuItem(
                        value: 'playlist', child: Text('Add to playlist')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
