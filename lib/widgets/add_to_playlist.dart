import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'track_thumb.dart';
import '../models/track.dart';
import '../services/library_service.dart';

/// Asks for a playlist name. Returns null if the user cancels.
Future<String?> askPlaylistName(BuildContext context,
    {String title = 'New playlist', String initial = ''}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Playlist name'),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

/// Bottom sheet listing the user's playlists (plus "New playlist") so a
/// song can be added to one with a single tap.
Future<void> showAddToPlaylistSheet(BuildContext context, Track track) {
  final messenger = ScaffoldMessenger.of(context);
  return showModalBottomSheet(
    context: context,
    builder: (sheetContext) {
      final library = sheetContext.watch<LibraryController>();
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text('Add "${track.title}" to…',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('New playlist'),
              onTap: () async {
                final name = await askPlaylistName(sheetContext);
                if (name == null) return;
                final playlist = library.createPlaylist(name);
                library.addToPlaylist(playlist, track);
                if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                messenger.showSnackBar(
                    SnackBar(content: Text('Added to ${playlist.name}')));
              },
            ),
            for (final playlist in library.playlists)
              ListTile(
                leading: const Icon(Icons.queue_music),
                title: Text(playlist.name),
                subtitle: Text(songCount(playlist.tracks.length)),
                onTap: () {
                  final added = library.addToPlaylist(playlist, track);
                  Navigator.of(sheetContext).pop();
                  messenger.showSnackBar(SnackBar(
                      content: Text(added
                          ? 'Added to ${playlist.name}'
                          : 'Already in ${playlist.name}')));
                },
              ),
          ],
        ),
      );
    },
  );
}
