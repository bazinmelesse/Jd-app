import 'package:flutter/material.dart';
import '../services/lyrics_service.dart';

/// Scrolling lyrics: the line being sung is big and bright and kept in the
/// middle; lines already sung fade out. Tap a line to jump there.
class LyricsView extends StatefulWidget {
  final Lyrics lyrics;
  final Duration position;
  final ValueChanged<Duration>? onSeek;

  const LyricsView(
      {super.key, required this.lyrics, required this.position, this.onSeek});

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  static const _lineHeight = 52.0;
  final _scroll = ScrollController();
  int _current = -1;

  @override
  void didUpdateWidget(LyricsView old) {
    super.didUpdateWidget(old);
    final index = widget.lyrics.indexAt(widget.position);
    if (index != _current) {
      _current = index;
      if (_scroll.hasClients && index >= 0) {
        // Keep the current line in the middle of the panel.
        final target = (index * _lineHeight -
                _scroll.position.viewportDimension / 2 +
                _lineHeight / 2)
            .clamp(0.0, _scroll.position.maxScrollExtent);
        _scroll.animateTo(target,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.lyrics.lines;
    final accent = Theme.of(context).colorScheme.primary;
    return ListView.builder(
      controller: _scroll,
      itemExtent: _lineHeight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: lines.length,
      itemBuilder: (context, i) {
        final active = widget.lyrics.synced && i == _current;
        final past = widget.lyrics.synced && i < _current;
        final time = lines[i].time;
        return GestureDetector(
          onTap: time == null || widget.onSeek == null
              ? null
              : () => widget.onSeek!(time),
          child: Align(
            alignment: Alignment.centerLeft,
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: active ? 22 : 17,
                fontWeight: active ? FontWeight.bold : FontWeight.w500,
                color: active
                    ? accent
                    : Colors.white.withValues(alpha: past ? 0.35 : 0.7),
              ),
              child: Text(lines[i].text,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
          ),
        );
      },
    );
  }
}
