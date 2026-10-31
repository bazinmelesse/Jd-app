import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/track_thumb.dart';
import '../main.dart';
import '../models/playlist.dart';
import '../services/audio_service.dart';
import '../services/library_service.dart';
import '../widgets/add_to_playlist.dart';
import 'stream_screen.dart';

/// One playlist: play songs, send them to a DJ deck, reorder (drag the
/// handle), remove, rename or delete the playlist.
class PlaylistScreen extends StatelessWidget {
  final Playlist playlist;

  const PlaylistScreen({super.key, required this.playlist});

  Future<void> _rename(BuildContext context) async {
    final library = context.read<LibraryController>();
    final name = await askPlaylistName(context,
        title: 'Rename playlist', initial: playlist.name);
    if (name != null) library.renamePlaylist(playlist, name);
  }

  Future<void> _delete(BuildContext context) async {
    final library = context.read<LibraryController>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${playlist.name}"?'),
        content: const Text('The songs stay on YouTube; only the list goes.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      library.deletePlaylist(playlist);
      Navigator.of(context).pop();
    }
  }

  void _loadOnDeck(BuildContext context, DeckId deck, int index) {
    final track = playlist.tracks[index];
    context.read<LibraryController>().addRecentTrack(track);
    context.read<MixerController>().loadTrackOnDeck(deck, track);
    // Jump straight to the DJ screen so the user sees it load.
    context.read<AppTabController>().value = AppTab.dj.index;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryController>();
    final length = playlist.totalLength;

    return Scaffold(
      appBar: AppBar(
        title: Text(playlist.name),
        actions: [
          IconButton(
              tooltip: 'Rename',
              icon: const Icon(Icons.edit),
              onPressed: () => _rename(context)),
          IconButton(
              tooltip: 'Delete playlist',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(context)),
        ],
      ),
      body: playlist.tracks.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'This playlist is empty. Search in the Stream tab and tap '
                  'the + next to a song to add it here.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '${songCount(playlist.tracks.length)}'
                    '${length > Duration.zero ? ' · ${length.inMinutes} min' : ''}',
                  ),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    itemCount: playlist.tracks.length,
                    onReorderItem: (from, to) =>
                        library.reorderPlaylist(playlist, from, to),
                    itemBuilder: (context, index) {
                      final track = playlist.tracks[index];
                      return ListTile(
                        key: ValueKey(track.videoId),
                        leading: TrackThumb(track.thumbnailUrl, width: 64),
                        title: Text(track.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                            [track.author, track.lengthLabel]
                                .where((s) => s.isNotEmpty)
                                .join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        onTap: () => openTrackPlayer(context, track,
                            queue: playlist.tracks),
                        trailing: PopupMenuButton<String>(
                          onSelected: (choice) {
                            switch (choice) {
                              case 'left':
                                _loadOnDeck(context, DeckId.left, index);
                              case 'right':
                                _loadOnDeck(context, DeckId.right, index);
                              case 'remove':
                                library.removeFromPlaylist(playlist, index);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                                value: 'left',
                                child: Text('Load on left deck')),
                            PopupMenuItem(
                                value: 'right',
                                child: Text('Load on right deck')),
                            PopupMenuItem(
                                value: 'remove',
                                child: Text('Remove from playlist')),
                          ],
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
