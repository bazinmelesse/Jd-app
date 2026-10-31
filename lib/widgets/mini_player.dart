import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../screens/video_player_screen.dart';
import '../services/player_service.dart';
import 'track_thumb.dart';

/// Opens the full-size player on what's playing.
void openFullPlayer(BuildContext context) {
  Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const VideoPlayerScreen()));
}

/// A slim bar above the tabs while music plays: what's on, play/pause,
/// next and the queue. Tap it for the full player. Lets you keep searching
/// and queueing songs without stopping the music.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final track = player.current;
    if (track == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: const Color(0xFF1C1C24),
      child: InkWell(
        onTap: () => openFullPlayer(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Progress along the top edge.
            SizedBox(
              height: 2,
              child: player.video == null
                  ? LinearProgressIndicator(
                      value: player.error != null ? 0 : null)
                  : ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: player.video!,
                      builder: (context, v, _) => LinearProgressIndicator(
                        value: v.duration.inMilliseconds == 0
                            ? 0
                            : v.position.inMilliseconds /
                                v.duration.inMilliseconds,
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child:
                        TrackThumb(track.thumbnailUrl, width: 64, height: 40),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13)),
                        Text(
                            player.error != null
                                ? "Couldn't play this one"
                                : player.upNext.isEmpty
                                    ? track.author
                                    : '${track.author} · ${player.upNext.length} up next',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  ),
                  if (player.loading)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  else
                    IconButton(
                      tooltip: player.isPlaying ? 'Pause' : 'Play',
                      color: scheme.primary,
                      iconSize: 32,
                      icon: Icon(player.isPlaying
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_filled),
                      onPressed: player.togglePlay,
                    ),
                  IconButton(
                    tooltip: 'Next',
                    icon: const Icon(Icons.skip_next),
                    onPressed: player.hasNext ? player.next : null,
                  ),
                  IconButton(
                    tooltip: 'Queue',
                    icon: const Icon(Icons.queue_music),
                    onPressed: () => showQueueSheet(context),
                  ),
                  IconButton(
                    tooltip: 'Stop',
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: player.stop,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
