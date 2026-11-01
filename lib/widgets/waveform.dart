import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/audio_service.dart';
import '../theme/dj_colors.dart';

/// Rebuilds every frame with the deck's current position, so time readouts
/// and waveforms glide smoothly instead of jumping between engine reports.
class DeckFrameBuilder extends StatefulWidget {
  final Deck deck;
  final Widget Function(BuildContext context, Duration position) builder;

  const DeckFrameBuilder(
      {super.key, required this.deck, required this.builder});

  @override
  State<DeckFrameBuilder> createState() => _DeckFrameBuilderState();
}

class _DeckFrameBuilderState extends State<DeckFrameBuilder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _frames =
      AnimationController(vsync: this, duration: const Duration(seconds: 1))
        ..repeat();

  @override
  void dispose() {
    _frames.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _frames,
        builder: (context, _) => widget.builder(context, widget.deck.position),
      );
}

/// Waveform color for a slice of sound: red for bass, through orange and
/// green, to cyan for bright cymbals.
Color toneColor(double tone, {double opacity = 1}) =>
    HSVColor.fromAHSV(opacity, (tone.clamp(0.0, 1.0) * 190), 0.85, 1).toColor();

/// Bucketed colors, so a waveform is drawn with a handful of paths.
const _toneBuckets = 10;

/// Both decks' waveforms across the top of the DJ screen, scrolling past a
/// red center line (the playhead): deck A grows upward, deck B downward,
/// with beat lines so you can see whether the two songs line up. Drag
/// either half sideways to move that song.
class CenterWaveform extends StatelessWidget {
  /// Seconds of music visible on each side of the playhead.
  static const secondsEachSide = 3.0;

  const CenterWaveform({super.key});

  @override
  Widget build(BuildContext context) {
    final mixer = context.watch<MixerController>();
    return LayoutBuilder(
      builder: (context, box) {
        final pxPerMs = box.maxWidth / (secondsEachSide * 2000);
        void drag(DragUpdateDetails d) {
          final deck =
              d.localPosition.dy < box.maxHeight / 2 ? mixer.left : mixer.right;
          if (deck.currentTrack == null) return;
          mixer.seek(deck.id,
              deck.position - Duration(milliseconds: d.delta.dx ~/ pxPerMs));
        }

        return GestureDetector(
          onHorizontalDragUpdate: drag,
          child: ClipRect(
            child: DeckFrameBuilder(
              deck: mixer.left,
              builder: (context, _) => CustomPaint(
                size: Size(box.maxWidth, box.maxHeight),
                painter: _CenterPainter(
                  mixer.left,
                  mixer.right,
                  mixer.left.position,
                  mixer.right.position,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CenterPainter extends CustomPainter {
  final Deck a, b;
  final Duration posA, posB;

  _CenterPainter(this.a, this.b, this.posA, this.posB);

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    _deck(canvas, size, a, posA, mid, -1);
    _deck(canvas, size, b, posB, mid, 1);
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid),
        Paint()..color = Colors.white24);
    // The playhead.
    canvas.drawLine(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        Paint()
          ..color = const Color(0xFFFF2D2D)
          ..strokeWidth = 2);
  }

  /// One deck's half: [dir] -1 draws upward from the middle, +1 downward.
  void _deck(
      Canvas canvas, Size size, Deck deck, Duration pos, double mid, int dir) {
    final peaks = deck.peaks;
    if (deck.currentTrack == null || peaks.isEmpty) {
      final tp = TextPainter(
        text: TextSpan(
            text: deck.currentTrack == null
                ? 'Deck ${DjColors.letter(deck.id)}: load a song'
                : 'Deck ${DjColors.letter(deck.id)}: no waveform for YouTube songs',
            style: const TextStyle(color: Colors.white38, fontSize: 11)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
          canvas,
          Offset(size.width * 0.25 - tp.width / 2,
              mid + dir * mid / 2 - tp.height / 2));
      return;
    }
    const halfMs = CenterWaveform.secondsEachSide * 1000;
    final msPerPx = halfMs * 2 / size.width;
    final pps = deck.peaksPerSecond;
    final center = pos.inMilliseconds.toDouble();
    final height = mid - 2;
    final paths = List.generate(_toneBuckets, (_) => Path());
    for (var x = 0; x < size.width; x += 2) {
      final ms = center + (x - size.width / 2) * msPerPx;
      if (ms < 0) continue;
      final i = (ms * pps / 1000).floor();
      if (i >= peaks.length) break;
      // Loudest of the slices this pixel column covers.
      final j =
          min(peaks.length, i + max(1, (msPerPx * 2 * pps / 1000).ceil()));
      var p = 0.0;
      var t = 0.0;
      for (var k = i; k < j; k++) {
        if (peaks[k] > p) {
          p = peaks[k];
          t = deck.tones.length > k ? deck.tones[k] : 0.5;
        }
      }
      final h = p * height;
      final bucket = (t * (_toneBuckets - 1)).round();
      paths[bucket].addRect(dir < 0
          ? Rect.fromLTWH(x.toDouble(), mid - h, 2, h)
          : Rect.fromLTWH(x.toDouble(), mid, 2, h));
    }
    final dim = deck.isPlaying ? 1.0 : 0.75;
    for (var k = 0; k < _toneBuckets; k++) {
      canvas.drawPath(paths[k],
          Paint()..color = toneColor(k / (_toneBuckets - 1), opacity: dim));
    }
    // Beat lines; every 4th (a bar) is taller.
    final beat = deck.beatLength;
    if (beat != null) {
      final beatMs = beat.inMicroseconds / 1000;
      final first = deck.firstBeat.inMicroseconds / 1000;
      final startN = ((center - halfMs - first) / beatMs).ceil();
      final endN = ((center + halfMs - first) / beatMs).floor();
      final line = Paint()
        ..color = Colors.white70
        ..strokeWidth = 1.2;
      for (var n = max(0, startN); n <= endN; n++) {
        final x = size.width / 2 + (first + n * beatMs - center) / msPerPx;
        final len = n % 4 == 0 ? height : height * 0.45;
        canvas.drawLine(Offset(x, mid), Offset(x, mid + dir * len), line);
      }
    }
    // Cue point.
    final cueX =
        size.width / 2 + (deck.cuePoint.inMilliseconds - center) / msPerPx;
    if (cueX >= 0 && cueX <= size.width) {
      final c = Paint()..color = DjColors.forDeck(deck.id);
      canvas.drawPath(
          Path()
            ..moveTo(cueX - 5, dir < 0 ? 0 : size.height)
            ..lineTo(cueX + 5, dir < 0 ? 0 : size.height)
            ..lineTo(cueX, dir < 0 ? 8 : size.height - 8)
            ..close(),
          c);
    }
  }

  @override
  bool shouldRepaint(_CenterPainter old) => true;
}

/// The whole song in one small strip: the part already played is bright,
/// with a red playhead and the cue and hot cue marks. Tap or drag to jump.
class OverviewWaveform extends StatelessWidget {
  final DeckId deckId;

  const OverviewWaveform({super.key, required this.deckId});

  @override
  Widget build(BuildContext context) {
    final mixer = context.watch<MixerController>();
    final deck = mixer.deckFor(deckId);
    return LayoutBuilder(
      builder: (context, box) {
        void seekTo(double dx) {
          if (deck.duration == Duration.zero) return;
          mixer.seek(
              deckId, deck.duration * (dx / box.maxWidth).clamp(0.0, 1.0));
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => seekTo(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => seekTo(d.localPosition.dx),
          child: DeckFrameBuilder(
            deck: deck,
            builder: (context, position) => CustomPaint(
              size: Size(box.maxWidth, box.maxHeight),
              painter: _OverviewPainter(deck, position),
            ),
          ),
        );
      },
    );
  }
}

class _OverviewPainter extends CustomPainter {
  final Deck deck;
  final Duration position;

  _OverviewPainter(this.deck, this.position);

  /// Downsampled peaks per song and width, so this isn't redone each frame.
  static final _cache = Expando<(int, Float32List, Float32List)>();

  @override
  void paint(Canvas canvas, Size size) {
    final peaks = deck.peaks;
    if (peaks.isEmpty || deck.duration == Duration.zero) {
      canvas.drawLine(Offset(0, size.height / 2),
          Offset(size.width, size.height / 2), Paint()..color = Colors.white12);
      return;
    }
    final cols = max(1, size.width ~/ 2);
    var cached = _cache[peaks];
    if (cached == null || cached.$1 != cols) {
      final p = Float32List(cols), t = Float32List(cols);
      final per = peaks.length / cols;
      for (var c = 0; c < cols; c++) {
        final from = (c * per).floor(),
            to = min(peaks.length, ((c + 1) * per).ceil());
        var tone = 0.0;
        for (var k = from; k < to; k++) {
          p[c] = max(p[c], peaks[k]);
          tone += deck.tones.length > k ? deck.tones[k] : 0.5;
        }
        t[c] = to > from ? tone / (to - from) : 0.5;
      }
      cached = (cols, p, t);
      _cache[peaks] = cached;
    }
    final played =
        position.inMilliseconds / max(1, deck.duration.inMilliseconds);
    final mid = size.height / 2;
    for (var c = 0; c < cols; c++) {
      final h = cached.$2[c] * mid;
      final isPlayed = c / cols <= played;
      canvas.drawRect(
          Rect.fromLTWH(c * 2.0, mid - h, 1.6, h * 2),
          Paint()
            ..color = toneColor(cached.$3[c], opacity: isPlayed ? 1 : 0.45));
    }
    final color = DjColors.forDeck(deck.id);
    void mark(Duration at, Color c) {
      final x = size.width * at.inMilliseconds / deck.duration.inMilliseconds;
      canvas.drawPath(
          Path()
            ..moveTo(x - 4, size.height)
            ..lineTo(x + 4, size.height)
            ..lineTo(x, size.height - 6)
            ..close(),
          Paint()..color = c);
    }

    for (final h in deck.hotCues) {
      if (h != null) mark(h, Colors.white);
    }
    mark(deck.cuePoint, color);
    final x = size.width * played;
    canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = const Color(0xFFFF2D2D)
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_OverviewPainter old) => true;
}
