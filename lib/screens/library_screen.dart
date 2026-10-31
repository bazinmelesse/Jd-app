import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/track_thumb.dart';
import '../models/playlist.dart';
import '../services/library_service.dart';
import '../widgets/add_to_playlist.dart';
import 'playlist_screen.dart';
import 'stream_screen.dart';

/// The "Library" tab: a dashboard of the user's playlists and the songs
/// they played recently.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  Future<void> _newPlaylist(BuildContext context) async {
    final library = context.read<LibraryController>();
    final name = await askPlaylistName(context);
    if (name == null || !context.mounted) return;
    final playlist = library.createPlaylist(name);
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PlaylistScreen(playlist: playlist)));
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryController>();
    final songCount =
        library.playlists.fold<int>(0, (sum, p) => sum + p.tracks.length);
    final width = MediaQuery.of(context).size.width;
    // 2 columns on phones, more on tablets.
    final columns = (width / 220).floor().clamp(2, 6);

    return Scaffold(
      appBar: AppBar(title: const Text('Library')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _newPlaylist(context),
        icon: const Icon(Icons.add),
        label: const Text('New playlist'),
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  _StatCard(
                      label: 'Playlists',
                      value: '${library.playlists.length}',
                      icon: Icons.queue_music),
                  const SizedBox(width: 12),
                  _StatCard(
                      label: 'Songs saved',
                      value: '$songCount',
                      icon: Icons.music_note),
                  const SizedBox(width: 12),
                  _StatCard(
                      label: 'Recently played',
                      value: '${library.recentTracks.length}',
                      icon: Icons.history),
                ],
              ),
            ),
          ),
          if (library.recentTracks.isNotEmpty) ...[
            const _SectionTitle('Recently played'),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 150,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: library.recentTracks.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final track = library.recentTracks[index];
                    return GestureDetector(
                      onTap: () => openTrackPlayer(context, track,
                          queue: library.recentTracks),
                      onLongPress: () => showAddToPlaylistSheet(context, track),
                      child: SizedBox(
                        width: 160,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: TrackThumb(track.thumbnailUrl,
                                  width: 160, height: 90),
                            ),
                            const SizedBox(height: 4),
                            Text(track.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
          const _SectionTitle('Your playlists'),
          if (library.playlists.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No playlists yet. Tap "New playlist", or tap the + next to '
                  'any search result to add it to one.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
              sliver: SliverGrid.count(
                crossAxisCount: columns,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.8,
                children: [
                  for (final playlist in library.playlists)
                    _PlaylistCard(playlist: playlist),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      sliver: SliverToBoxAdapter(
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatCard(
      {required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20),
              const SizedBox(height: 6),
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  final Playlist playlist;
  const _PlaylistCard({required this.playlist});

  @override
  Widget build(BuildContext context) {
    final cover = playlist.coverUrl;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => PlaylistScreen(playlist: playlist))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: cover == null
                  ? Container(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      child: const Icon(Icons.queue_music, size: 48),
                    )
                  : TrackThumb(cover),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(playlist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(songCount(playlist.tracks.length),
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
