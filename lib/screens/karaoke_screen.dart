import 'package:flutter/material.dart';
import '../widgets/track_search_panel.dart';
import 'stream_screen.dart';
import '../widgets/youtube_key_gate.dart';

/// Adds "karaoke" to a search unless the user already typed it.
String karaokeQuery(String query) =>
    query.toLowerCase().contains('karaoke') ? query : '$query karaoke';

/// The "Karaoke" tab: type a song, get karaoke versions from YouTube (music
/// without the lead vocals, lyrics on screen) and sing along full screen.
class KaraokeScreen extends StatelessWidget {
  const KaraokeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Karaoke')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: YoutubeKeyGate(
          child: TrackSearchPanel(
            hintText: 'What do you want to sing?',
            queryTransform: karaokeQuery,
            onTrackTap: (track, results) => openTrackPlayer(context, track,
                queue: results, showLyrics: false),
            emptyState: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.mic_external_on, size: 56),
                    SizedBox(height: 12),
                    Text(
                      'Search a song or artist and pick a karaoke version.\n'
                      'Tap the lyrics button in the player for scrolling lyrics.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
