import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'track_thumb.dart';
import '../models/track.dart';
import '../services/audio_service.dart';
import '../services/library_service.dart';
import 'add_to_playlist.dart';

/// Search box + recent-search chips + results list, shared by the Stream tab
/// and the DJ deck's "Load track" sheet. Every result has an
/// "add to playlist" button.
class TrackSearchPanel extends StatefulWidget {
  final String hintText;

  /// Called with the tapped song and the full list it was in.
  final void Function(Track track, List<Track> results) onTrackTap;

  /// Shown under the recent searches while there are no results yet.
  final Widget? emptyState;

  /// Rewrites what's sent to YouTube (e.g. adds "karaoke"); the history
  /// keeps what the user actually typed.
  final String Function(String query)? queryTransform;

  /// Replaces the "add to playlist" button on each result.
  final Widget Function(Track track)? trailingBuilder;

  const TrackSearchPanel({
    super.key,
    required this.hintText,
    required this.onTrackTap,
    this.emptyState,
    this.queryTransform,
    this.trailingBuilder,
  });

  @override
  State<TrackSearchPanel> createState() => _TrackSearchPanelState();
}

class _TrackSearchPanelState extends State<TrackSearchPanel> {
  final _controller = TextEditingController();
  List<Track> _results = [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _runSearch([String? query]) async {
    if (query != null) _controller.text = query;
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    context.read<LibraryController>().addSearch(q);
    final youtube = context.read<MixerController>().youtube;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await youtube.search(widget.queryTransform?.call(q) ?? q);
      if (mounted) setState(() => _results = results);
    } catch (e) {
      if (mounted) setState(() => _error = 'Search failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryController>();

    return Column(
      children: [
        TextField(
          controller: _controller,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: widget.hintText,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () => setState(() {
                _controller.clear();
                _results = [];
              }),
            ),
          ),
          onSubmitted: (_) => _runSearch(),
        ),
        if (library.recentSearches.isNotEmpty)
          SizedBox(
            height: 48,
            child: Row(
              children: [
                Expanded(
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final q in library.recentSearches)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: InputChip(
                            avatar: const Icon(Icons.history, size: 16),
                            label: Text(q),
                            onPressed: () => _runSearch(q),
                            onDeleted: () => library.removeSearch(q),
                          ),
                        ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: library.clearSearches,
                  child: const Text('Clear'),
                ),
              ],
            ),
          ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
        Expanded(
          child: _results.isEmpty && !_loading
              ? (widget.emptyState ??
                  const Center(
                      child: Text('Search for something to listen to')))
              : ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    final track = _results[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: TrackThumb(track.thumbnailUrl, width: 64),
                      title: Text(track.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                          [track.author, track.lengthLabel]
                              .where((s) => s.isNotEmpty)
                              .join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      trailing: widget.trailingBuilder?.call(track) ??
                          IconButton(
                            tooltip: 'Add to playlist',
                            icon: const Icon(Icons.playlist_add),
                            onPressed: () =>
                                showAddToPlaylistSheet(context, track),
                          ),
                      onTap: () => widget.onTrackTap(track, _results),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
