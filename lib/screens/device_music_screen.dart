import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/track.dart';
import '../services/audio_service.dart';
import '../services/engine/engine_bridge.dart';
import '../services/player_service.dart';
import '../theme/dj_colors.dart';
import 'video_player_screen.dart';

/// Web version: the songs opened from this device in this visit. Browsers
/// can't keep a file between visits, so the list starts empty each time.
class DeviceSongs extends ChangeNotifier {
  final List<Track> songs = [];

  /// Opens the file picker. Call it straight from a tap. Returns the new
  /// songs (empty if the user picked nothing).
  Future<List<Track>> open({bool multiple = true}) async {
    final picked = await pickLocalSongs(multiple: multiple);
    final tracks = [for (final s in picked) s.toTrack()];
    songs.addAll(tracks);
    if (tracks.isNotEmpty) notifyListeners();
    return tracks;
  }

  void remove(Track t) {
    songs.remove(t);
    notifyListeners();
  }
}

/// The big "open songs" button.
class OpenSongsButton extends StatelessWidget {
  final void Function(List<Track> picked)? onPicked;
  final bool multiple;
  final String label;

  const OpenSongsButton(
      {super.key,
      this.onPicked,
      this.multiple = true,
      this.label = 'Open songs from this device'});

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          backgroundColor: DjColors.deckA,
          foregroundColor: Colors.black,
          textStyle: const TextStyle(fontWeight: FontWeight.w600)),
      icon: const Icon(Icons.folder_open),
      label: Text(label),
      // No await before open(): the browser only shows the picker from a tap.
      onPressed: () => context
          .read<DeviceSongs>()
          .open(multiple: multiple)
          .then((picked) => onPicked?.call(picked)),
    );
  }
}

/// The Stream tab in the web version: play your own songs.
class DeviceMusicScreen extends StatelessWidget {
  const DeviceMusicScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final device = context.watch<DeviceSongs>();
    final player = context.read<PlayerController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('My music'),
        actions: [
          IconButton(
            tooltip: 'Queue',
            icon: const Icon(Icons.queue_music),
            onPressed: () => showQueueSheet(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          OpenSongsButton(onPicked: (picked) {
            if (picked.isNotEmpty && player.current == null) {
              player.playQueue(device.songs, device.songs.indexOf(picked.first),
                  lyrics: false);
            }
          }),
          const SizedBox(height: 12),
          const _WebNote(),
          const SizedBox(height: 8),
          if (device.songs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Text(
                'Pick MP3 or M4A files from your phone (Files app, iCloud '
                'Drive, Downloads). Then try DJ Mode: tap LOAD on a deck.',
                textAlign: TextAlign.center,
              ),
            ),
          for (final (i, t) in device.songs.indexed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(child: Icon(Icons.music_note)),
              title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(t.author),
              onTap: () => player.playQueue(device.songs, i, lyrics: false),
              trailing: PopupMenuButton<String>(
                onSelected: (choice) {
                  final mixer = context.read<MixerController>();
                  switch (choice) {
                    case 'next':
                      player.playNext(t);
                    case 'queue':
                      player.addToQueue(t);
                    case 'a':
                      mixer.loadTrackOnDeck(DeckId.left, t);
                    case 'b':
                      mixer.loadTrackOnDeck(DeckId.right, t);
                    case 'remove':
                      device.remove(t);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'next', child: Text('Play next')),
                  PopupMenuItem(value: 'queue', child: Text('Add to queue')),
                  PopupMenuItem(value: 'a', child: Text('Load on deck A')),
                  PopupMenuItem(value: 'b', child: Text('Load on deck B')),
                  PopupMenuItem(value: 'remove', child: Text('Remove')),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _WebNote extends StatelessWidget {
  const _WebNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DjColors.panel,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Browser test version. YouTube search and karaoke are in the '
              'Android app; here you play songs saved on your device.',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// Karaoke tab in the web version.
class WebKaraokeNote extends StatelessWidget {
  const WebKaraokeNote({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Karaoke')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Karaoke searches YouTube, which only works in the Android app '
            'for now.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

/// DJ Mode's LOAD sheet in the web version.
class DeviceSongSheet extends StatelessWidget {
  final DeckId targetDeck;
  const DeviceSongSheet({super.key, required this.targetDeck});

  @override
  Widget build(BuildContext context) {
    final device = context.watch<DeviceSongs>();
    final mixer = context.read<MixerController>();
    void load(Track t) {
      Navigator.of(context).pop();
      mixer.loadTrackOnDeck(targetDeck, t);
    }

    return SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            Text(
                'Load deck ${targetDeck == DeckId.left ? 'A' : 'B'}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            OpenSongsButton(
              multiple: false,
              label: 'Open a song from this device',
              onPicked: (picked) {
                if (picked.isNotEmpty) load(picked.first);
              },
            ),
            if (device.songs.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 16, bottom: 4),
                child: Text('Already opened',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            for (final t in device.songs)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.music_note),
                title:
                    Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(t.author),
                onTap: () => load(t),
              ),
          ],
        ),
      ),
    );
  }
}
