import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/audio_service.dart';
import '../theme/dj_colors.dart';
import 'track_thumb.dart';

/// A single spinning-vinyl platter. Handles:
/// - continuous rotation animation while playing
/// - drag-to-scratch (spin the record with your finger to nudge playback)
/// - tap to load a song when the deck is empty
class TurntableWidget extends StatefulWidget {
  final DeckId deckId;
  final VoidCallback onLoadTrackPressed;

  const TurntableWidget({
    super.key,
    required this.deckId,
    required this.onLoadTrackPressed,
  });

  @override
  State<TurntableWidget> createState() => _TurntableWidgetState();
}

/// One revolution at 33 1/3 RPM.
const _msPerTurn = 1800;

class _TurntableWidgetState extends State<TurntableWidget>
    with SingleTickerProviderStateMixin {
  /// Runs every frame so the record's angle can follow the song smoothly.
  late final AnimationController _frames;

  // Scratch-gesture bookkeeping
  double _lastAngle = 0;
  bool _isScratching = false;

  /// While scratching, the record is turned by the finger (in turns).
  double _fingerTurns = 0;

  @override
  void initState() {
    super.initState();
    _frames =
        AnimationController(vsync: this, duration: const Duration(seconds: 1))
          ..repeat();
  }

  @override
  void dispose() {
    _frames.dispose();
    super.dispose();
  }

  /// The record's angle comes from the song position: one turn per 1.8 s of
  /// music, so the vinyl and the sound always agree.
  double _turnsFor(Deck deck) => _isScratching
      ? _fingerTurns
      : deck.position.inMicroseconds / (_msPerTurn * 1000);

  double _angleFromOffset(Offset localPosition, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final vector = localPosition - center;
    return atan2(vector.dy, vector.dx);
  }

  // Raw pointer events (not a drag gesture) so the record grabs the
  // instant a finger touches it, with no "drag a bit first" delay.
  void _onPointerDown(PointerDownEvent event, Deck deck, Size size) {
    if (deck.currentTrack == null || _isScratching) return;
    _fingerTurns = _turnsFor(deck);
    setState(() => _isScratching = true);
    _lastAngle = _angleFromOffset(event.localPosition, size);
    deck.scratchStart();
  }

  void _onPointerMove(PointerMoveEvent event, Deck deck, Size size) {
    if (!_isScratching) return;
    // Ignore touches right on the spindle, where the angle jumps wildly.
    final center = Offset(size.width / 2, size.height / 2);
    if ((event.localPosition - center).distance < size.width * 0.06) return;
    final angle = _angleFromOffset(event.localPosition, size);
    var delta = angle - _lastAngle;

    // Normalize angle wraparound (-pi..pi)
    if (delta > pi) delta -= 2 * pi;
    if (delta < -pi) delta += 2 * pi;
    _lastAngle = angle;

    // One full turn of the record = 1.8 s of music, like real vinyl. The
    // engine's playhead chases this smoothly, forwards or backwards.
    final turns = delta / (2 * pi);
    _fingerTurns += turns;
    deck.scratchMove(turns * _msPerTurn);
  }

  void _onPointerUp(Deck deck) {
    if (!_isScratching) return;
    setState(() => _isScratching = false);
    deck.scratchEnd();
  }

  @override
  Widget build(BuildContext context) {
    final mixer = context.watch<MixerController>();
    final deck = mixer.deckFor(widget.deckId);
    final color = DjColors.forDeck(widget.deckId);
    final track = deck.currentTrack;
    final spinning = deck.isPlaying;

    // Size the deck to whichever is smaller, width or height, so it fits
    // phones and tablets alike. The record sits a little left of center to
    // leave room for the tonearm, like a real turntable.
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = min(constraints.maxWidth, constraints.maxHeight);
        final recordSide = side * 0.86;
        final size = Size(recordSide, recordSide);
        final labelSize = recordSide * 0.38;
        return Center(
          child: SizedBox(
            width: side,
            height: side,
            child: Stack(
              children: [
                // Platter shadow and the deck-colored light at the bottom left.
                Positioned(
                  left: side * 0.03,
                  top: side * 0.07,
                  child: Container(
                    width: recordSide,
                    height: recordSide,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(colors: [
                        Color(0xFF2A2A30),
                        Color(0xFF141418),
                      ]),
                      boxShadow: [
                        const BoxShadow(
                            color: Colors.black87,
                            blurRadius: 18,
                            offset: Offset(0, 6)),
                        BoxShadow(
                          color: color.withValues(
                              alpha: spinning || _isScratching ? 0.45 : 0.15),
                          blurRadius: side * 0.1,
                          offset: Offset(-side * 0.12, side * 0.14),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: side * 0.03,
                  top: side * 0.07,
                  child: Listener(
                    onPointerDown: (e) => _onPointerDown(e, deck, size),
                    onPointerMove: (e) => _onPointerMove(e, deck, size),
                    onPointerUp: (_) => _onPointerUp(deck),
                    onPointerCancel: (_) => _onPointerUp(deck),
                    child: GestureDetector(
                      onTap: track == null ? widget.onLoadTrackPressed : null,
                      child: SizedBox.fromSize(
                        size: size,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // The record: grooves, artwork label with a ring in
                            // the deck's color, and a marker to see it turn.
                            AnimatedBuilder(
                              animation: _frames,
                              builder: (context, child) => Transform.rotate(
                                angle: _turnsFor(deck) * 2 * pi,
                                child: child,
                              ),
                              child: SizedBox.fromSize(
                                size: size * 0.96,
                                child: CustomPaint(
                                  painter: _VinylPainter(color),
                                  child: Center(
                                    child: Container(
                                      width: labelSize,
                                      height: labelSize,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: color,
                                            width: max(2, labelSize * 0.035)),
                                      ),
                                      child: ClipOval(
                                        child: track == null
                                            ? Container(
                                                color: const Color(0xFF1C1C22),
                                                alignment: Alignment.center,
                                                child: Text(
                                                  'DJ MUSI\nDECK ${DjColors.letter(widget.deckId)}',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                      color: color,
                                                      fontSize:
                                                          labelSize * 0.12,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      letterSpacing: 1),
                                                ),
                                              )
                                            : TrackThumb(track.thumbnailUrl,
                                                width: labelSize,
                                                height: labelSize),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            // Spindle
                            Container(
                              width: recordSide * 0.03,
                              height: recordSide * 0.03,
                              decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color(0xFFD0D0D8)),
                            ),
                            // Fixed light reflection, so the vinyl looks glossy.
                            IgnorePointer(
                              child: Container(
                                width: recordSide * 0.96,
                                height: recordSide * 0.96,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: SweepGradient(
                                    colors: [
                                      Colors.white.withValues(alpha: 0),
                                      Colors.white.withValues(alpha: 0.06),
                                      Colors.white.withValues(alpha: 0),
                                      Colors.white.withValues(alpha: 0),
                                      Colors.white.withValues(alpha: 0.06),
                                      Colors.white.withValues(alpha: 0),
                                    ],
                                    stops: const [
                                      0.05,
                                      0.12,
                                      0.2,
                                      0.55,
                                      0.62,
                                      0.7
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            if (deck.isLoading)
                              SizedBox(
                                width: labelSize * 0.6,
                                height: labelSize * 0.6,
                                child: CircularProgressIndicator(color: color),
                              ),
                            if (track == null && !deck.isLoading && side > 150)
                              Positioned(
                                bottom: recordSide * 0.16,
                                child: Text('Tap to load a song',
                                    style: TextStyle(
                                        color: DjColors.textDim,
                                        fontSize: max(10, side * 0.04))),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Tonearm: rests outside while stopped, on the record while
                // a song plays.
                Positioned.fill(
                  child: IgnorePointer(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: track != null && spinning ? 1 : 0),
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeInOut,
                      builder: (context, t, _) =>
                          CustomPaint(painter: _TonearmPainter(t, color)),
                    ),
                  ),
                ),
                // Pitch bend: hold + or - to nudge the song faster or
                // slower, to line up its beats with the other deck by ear.
                Positioned(
                  left: 0,
                  top: 0,
                  child: Column(
                    children: [
                      _BendButton(
                          icon: Icons.add,
                          size: max(28, side * 0.1),
                          onHold: (on) =>
                              mixer.bend(widget.deckId, on ? 1 : 0)),
                      _BendButton(
                          icon: Icons.remove,
                          size: max(28, side * 0.1),
                          onHold: (on) =>
                              mixer.bend(widget.deckId, on ? -1 : 0)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A press-and-hold button (pitch bend).
class _BendButton extends StatefulWidget {
  final IconData icon;
  final double size;
  final ValueChanged<bool> onHold;

  const _BendButton(
      {required this.icon, required this.size, required this.onHold});

  @override
  State<_BendButton> createState() => _BendButtonState();
}

class _BendButtonState extends State<_BendButton> {
  bool _down = false;

  void _set(bool down) {
    if (_down == down) return;
    setState(() => _down = down);
    widget.onHold(down);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Icon(widget.icon,
            size: widget.size * 0.7,
            color: _down ? Colors.white : DjColors.textDim),
      ),
    );
  }
}

/// Draws the tonearm from its pivot at the top right. [t] is 0 when resting
/// and 1 when the needle is on the record.
class _TonearmPainter extends CustomPainter {
  final double t;
  final Color accent;

  _TonearmPainter(this.t, this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final pivot = Offset(s * 0.9, s * 0.12);
    // Pivot base.
    canvas.drawCircle(
        pivot, s * 0.075, Paint()..color = const Color(0xFF1E1E24));
    canvas.drawCircle(
        pivot,
        s * 0.075,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white12);
    canvas.drawCircle(
        pivot, s * 0.035, Paint()..color = const Color(0xFF3A3A42));
    // Arm angle: straight down while resting, swung onto the record.
    final angle = lerpDouble(0.02, 0.38, t);
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(angle);
    final arm = Paint()
      ..color = const Color(0xFFB8B8C0)
      ..strokeWidth = max(2.5, s * 0.014)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(0, -s * 0.05)
      ..lineTo(0, s * 0.52)
      ..quadraticBezierTo(0, s * 0.62, -s * 0.06, s * 0.68);
    canvas.drawPath(path, arm);
    // Headshell with a needle light in the deck's color.
    canvas.translate(-s * 0.06, s * 0.68);
    canvas.rotate(0.6);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset.zero, width: s * 0.035, height: s * 0.08),
            const Radius.circular(3)),
        Paint()..color = const Color(0xFF2A2A30));
    canvas.drawCircle(Offset(0, s * 0.035), s * 0.012, Paint()..color = accent);
    canvas.restore();
  }

  static double lerpDouble(double a, double b, double t) => a + (b - a) * t;

  @override
  bool shouldRepaint(_TonearmPainter old) => old.t != t || old.accent != accent;
}

/// Paints a black record with fine grooves and a colored marker line.
class _VinylPainter extends CustomPainter {
  final Color accent;
  _VinylPainter(this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;

    canvas.drawCircle(center, radius, Paint()..color = const Color(0xFF050507));

    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    for (var r = radius * 0.22; r < radius * 0.97; r += radius * 0.022) {
      groove.color =
          Colors.white.withValues(alpha: 0.035 + (r / radius) * 0.03);
      canvas.drawCircle(center, r, groove);
    }

    // A darker band and a thin marker, so you can see the record turn.
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.65),
      -pi / 2 - 0.5,
      1.0,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.6
        ..color = Colors.white.withValues(alpha: 0.035),
    );
    canvas.drawLine(
      center + Offset(0, -radius * 0.42),
      center + Offset(0, -radius * 0.96),
      Paint()
        ..color = accent.withValues(alpha: 0.6)
        ..strokeWidth = max(1.5, radius * 0.012)
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_VinylPainter old) => old.accent != accent;
}
