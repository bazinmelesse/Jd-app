import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'track_thumb.dart';
import '../models/track.dart';
import '../services/audio_service.dart';
import '../services/library_service.dart';
import 'track_search_panel.dart';
import 'youtube_key_gate.dart';
import '../screens/device_music_screen.dart';
import '../services/engine/engine_bridge.dart';
import '../services/engine/local_song.dart';

/// Bottom sheet: search YouTube (or pick from a playlist), tap a song to
/// load it onto the target deck.
class TrackSearchSheet extends StatelessWidget {
  final DeckId targetDeck;

  const TrackSearchSheet({super.key, required this.targetDeck});

  @override
  Widget build(BuildContext context) {
    void load(Track track) {
      Navigator.of(context).pop();
      if (!track.isLocal) {
        context.read<LibraryController>().addRecentTrack(track);
      }
      context.read<MixerController>().loadTrackOnDeck(targetDeck, track);
    }

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            if (isWebEngine) ...[
              OpenSongsButton(
                multiple: false,
                label: 'Open a song from this device',
                onPicked: (picked) {
                  if (picked.isNotEmpty) {
                    Navigator.of(context).pop();
                    context
                        .read<MixerController>()
                        .loadTrackOnDeck(targetDeck, picked.first);
                  }
                },
              ),
              const SizedBox(height: 8),
            ],
            Expanded(
              child: YoutubeKeyGate(
                child: TrackSearchPanel(
                  hintText: 'Search YouTube...',
                  onTrackTap: (track, _) => load(track),
                  emptyState: _PlaylistPicker(onTrackTap: load),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Before searching, lets the DJ pick straight from their playlists.
class _PlaylistPicker extends StatelessWidget {
  final void Function(Track track) onTrackTap;

  const _PlaylistPicker({required this.onTrackTap});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryController>();
    if (library.playlists.isEmpty) {
      return const Center(
          child:
              Text('Search for a song, or make playlists in the Library tab'));
    }
    return ListView(
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('From your playlists',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        for (final playlist in library.playlists)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            leading: const Icon(Icons.queue_music),
            title: Text(playlist.name),
            subtitle: Text(songCount(playlist.tracks.length)),
            children: [
              for (final track in playlist.tracks)
                ListTile(
                  dense: true,
                  leading: TrackThumb(track.thumbnailUrl, width: 48),
                  title: Text(track.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(track.author),
                  onTap: () => onTrackTap(track),
                ),
            ],
          ),
      ],
    );
  }
}
