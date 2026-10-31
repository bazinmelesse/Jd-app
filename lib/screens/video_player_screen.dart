import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../models/track.dart';
import '../services/lyrics_service.dart';
import '../services/player_service.dart';
import '../widgets/add_to_playlist.dart';
import '../widgets/lyrics_view.dart';
import '../widgets/track_thumb.dart';

/// The full-size player: the video, music-app style controls (seek bar,
/// play/pause, skip 10 s, previous/next, shuffle, repeat, volume) and the
/// queue, with lyrics that can scroll underneath in time with the music.
/// It shows whatever the shared [PlayerController] is playing; closing it
/// keeps the music going in the mini player.
class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({super.key});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  /// While the seek bar is being dragged, the spot under the finger.
  double? _dragMs;

  late bool _lyricsOn = context.read<PlayerController>().lyricsWanted;
  Lyrics? _lyrics;
  bool _lyricsLoading = false;
  String? _lyricsFor; // videoId the lyrics were looked up for

  /// Stands in for the player while a song loads.
  final _idle = ValueNotifier(const VideoPlayerValue.uninitialized());

  @override
  void dispose() {
    _idle.dispose();
    super.dispose();
  }

  Future<void> _loadLyrics(Track track) async {
    if (_lyricsFor == track.videoId) return;
    _lyricsFor = track.videoId;
    _lyrics = null;
    _lyricsLoading = true;
    Lyrics? found;
    try {
      found = await LyricsService().find(track);
    } catch (_) {
      found = null; // offline or service down: just show "not found"
    }
    if (mounted && _lyricsFor == track.videoId) {
      setState(() {
        _lyrics = found;
        _lyricsLoading = false;
      });
    }
  }

  Widget _lyricsPanel(VideoPlayerController? controller) {
    if (_lyricsLoading || controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final lyrics = _lyrics;
    if (lyrics == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text("Couldn't find lyrics for this song",
              style: TextStyle(color: Colors.grey)),
        ),
      );
    }
    return Column(
      children: [
        if (!lyrics.synced)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Lyrics (not timed for this song)',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
          ),
        Expanded(
          child: ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: controller,
            builder: (context, value, _) => LyricsView(
              lyrics: lyrics,
              position: value.position,
              onSeek: controller.seekTo,
            ),
          ),
        ),
      ],
    );
  }

  /// The video itself. Double-tap the left or right side to skip 10 s,
  /// tap to play/pause.
  Widget _video(PlayerController player) {
    final controller = player.video;
    if (player.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(player.error!, textAlign: TextAlign.center),
              TextButton.icon(
                onPressed: player.next,
                icon: const Icon(Icons.skip_next),
                label: const Text('Play the next song'),
              ),
            ],
          ),
        ),
      );
    }
    if (controller == null) {
      return const AspectRatio(
        aspectRatio: 16 / 9,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return AspectRatio(
      aspectRatio: controller.value.aspectRatio,
      child: LayoutBuilder(
        builder: (context, box) => GestureDetector(
          onTap: player.togglePlay,
          onDoubleTapDown: (d) =>
              player.skip(d.localPosition.dx < box.maxWidth / 2 ? -10 : 10),
          onDoubleTap: () {},
          child: VideoPlayer(controller),
        ),
      ),
    );
  }

  String _clock(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
  }

  Widget _controls(PlayerController player, Track track) {
    final scheme = Theme.of(context).colorScheme;
    final controller = player.video;
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller ?? _idle,
      builder: (context, value, _) {
        final total = value.duration.inMilliseconds.toDouble();
        final pos = (_dragMs ?? value.position.inMilliseconds.toDouble())
            .clamp(0.0, max(total, 1.0))
            .toDouble();
        final ready = controller != null;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title, artist and "add to playlist".
              Row(
                children: [
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        Text(track.author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.grey)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Add to playlist',
                    icon: const Icon(Icons.playlist_add),
                    onPressed: () => showAddToPlaylistSheet(context, track),
                  ),
                ],
              ),
              // Seek bar with elapsed and remaining time.
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 14),
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 7),
                ),
                child: Slider(
                  value: pos,
                  max: max(total, 1.0),
                  onChanged: ready && total > 0
                      ? (v) => setState(() => _dragMs = v)
                      : null,
                  onChangeEnd: ready
                      ? (v) {
                          player.seek(Duration(milliseconds: v.round()));
                          setState(() => _dragMs = null);
                        }
                      : null,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_clock(Duration(milliseconds: pos.round())),
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey)),
                    Text(
                        '-${_clock(Duration(milliseconds: (total - pos).round()))}',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              // Shuffle, previous, -10 s, play/pause, +10 s, next, repeat.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Shuffle',
                      color: player.shuffle ? scheme.primary : null,
                      icon: const Icon(Icons.shuffle),
                      onPressed: player.toggleShuffle,
                    ),
                    IconButton(
                      tooltip: 'Previous',
                      iconSize: 34,
                      icon: const Icon(Icons.skip_previous),
                      onPressed: player.previous,
                    ),
                    IconButton(
                      tooltip: 'Back 10 seconds',
                      icon: const Icon(Icons.replay_10),
                      onPressed: ready ? () => player.skip(-10) : null,
                    ),
                    IconButton(
                      tooltip: value.isPlaying ? 'Pause' : 'Play',
                      iconSize: 64,
                      color: scheme.primary,
                      icon: Icon(value.isPlaying
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_filled),
                      onPressed: ready ? player.togglePlay : null,
                    ),
                    IconButton(
                      tooltip: 'Forward 10 seconds',
                      icon: const Icon(Icons.forward_10),
                      onPressed: ready ? () => player.skip(10) : null,
                    ),
                    IconButton(
                      tooltip: 'Next',
                      iconSize: 34,
                      icon: const Icon(Icons.skip_next),
                      onPressed: player.hasNext ? player.next : null,
                    ),
                    IconButton(
                      tooltip: switch (player.repeat) {
                        PlayRepeat.off => 'Repeat is off',
                        PlayRepeat.all => 'Repeating all',
                        PlayRepeat.one => 'Repeating this song',
                      },
                      color: player.repeat == PlayRepeat.off
                          ? null
                          : scheme.primary,
                      icon: Icon(player.repeat == PlayRepeat.one
                          ? Icons.repeat_one
                          : Icons.repeat),
                      onPressed: player.cycleRepeat,
                    ),
                  ],
                ),
              ),
              // Volume, with a mute button, and the queue.
              Row(
                children: [
                  IconButton(
                    tooltip: player.muted ? 'Unmute' : 'Mute',
                    icon: Icon(player.muted || player.volume == 0
                        ? Icons.volume_off
                        : player.volume < 0.5
                            ? Icons.volume_down
                            : Icons.volume_up),
                    onPressed: player.toggleMute,
                  ),
                  Expanded(
                    child: Slider(
                      value: player.muted ? 0 : player.volume,
                      onChanged: player.setVolume,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Queue',
                    icon: const Icon(Icons.queue_music),
                    onPressed: () => showQueueSheet(context),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final track = player.current;
    if (track == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Nothing is playing')),
      );
    }
    if (_lyricsOn) _loadLyrics(track);
    final controller = player.video;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Minimize',
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
            player.queue.length > 1
                ? 'Song ${player.index + 1} of ${player.queue.length}'
                : 'Now playing',
            style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            tooltip: _lyricsOn ? 'Hide lyrics' : 'Show lyrics',
            icon: Icon(_lyricsOn ? Icons.lyrics : Icons.lyrics_outlined),
            onPressed: () => setState(() => _lyricsOn = !_lyricsOn),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            final wide = box.maxWidth > box.maxHeight * 1.1;
            if (wide) {
              // Tablets in landscape: video and controls on the left,
              // lyrics on the right when they're on.
              final left = Column(
                children: [
                  Expanded(child: Center(child: _video(player))),
                  _controls(player, track),
                ],
              );
              return _lyricsOn
                  ? Row(
                      children: [
                        Expanded(flex: 3, child: left),
                        Expanded(flex: 2, child: _lyricsPanel(controller)),
                      ],
                    )
                  : left;
            }
            return Column(
              children: [
                if (_lyricsOn)
                  _video(player)
                else
                  Expanded(child: Center(child: _video(player))),
                _controls(player, track),
                if (_lyricsOn) Expanded(child: _lyricsPanel(controller)),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The queue: what's playing, what's next (drag to reorder, swipe to
/// remove) and the autoplay switch.
void showQueueSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => SizedBox(
      height: MediaQuery.of(sheet).size.height * 0.75,
      child: const _QueueSheet(),
    ),
  );
}

class _QueueSheet extends StatelessWidget {
  const _QueueSheet();

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final current = player.current;
    final first = player.index + 1;
    final upNext = player.upNext;
    return SafeArea(
      child: Column(
        children: [
          if (current != null)
            ListTile(
              leading: TrackThumb(current.thumbnailUrl, width: 56),
              title: Text(current.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: const Text('Now playing'),
              trailing: const Icon(Icons.equalizer),
            ),
          SwitchListTile(
            title: const Text('Autoplay'),
            subtitle: const Text(
                'When the queue ends, keep playing songs like the ones you play and search for'),
            value: player.autoplay,
            onChanged: player.setAutoplay,
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Row(
              children: [
                const Text('Up next',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Spacer(),
                if (player.findingSuggestions)
                  const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
          ),
          Expanded(
            child: upNext.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                          'Nothing queued. Search for songs and tap + to add them.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey)),
                    ),
                  )
                : ReorderableListView.builder(
                    itemCount: upNext.length,
                    onReorderItem: (from, to) =>
                        player.move(first + from, first + to),
                    itemBuilder: (context, i) {
                      final t = upNext[i];
                      return Dismissible(
                        key: ValueKey('${t.videoId}-${first + i}'),
                        direction: DismissDirection.endToStart,
                        onDismissed: (_) => player.removeAt(first + i),
                        background: Container(
                          color: Colors.red.shade900,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child: const Icon(Icons.delete),
                        ),
                        child: ListTile(
                          leading: TrackThumb(t.thumbnailUrl, width: 56),
                          title: Text(t.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                              player.suggested.contains(t.videoId)
                                  ? 'Suggested · ${t.author}'
                                  : t.author,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          onTap: () => player.jumpTo(first + i),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
