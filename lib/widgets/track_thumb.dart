import 'package:flutter/material.dart';

/// A YouTube thumbnail that falls back to a music-note box when the image
/// can't load (offline, removed video).
class TrackThumb extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;

  const TrackThumb(this.url, {super.key, this.width, this.height});

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: width,
      height: height,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.music_note),
    );
    if (url.isEmpty) return fallback;
    return Image.network(url,
        width: width,
        height: height,
        fit: BoxFit.cover,
        // YouTube's image server doesn't allow the browser to read the
        // pixels, so the web version shows thumbnails as plain <img> tags.
        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
        errorBuilder: (_, __, ___) => fallback);
  }
}

String songCount(int n) => n == 1 ? '1 song' : '$n songs';
