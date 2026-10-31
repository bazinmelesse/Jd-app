import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/audio_service.dart';
import '../theme/dj_colors.dart';

/// What a deck shows in place of its turntable. Tapping the same button
/// again goes back to the turntable.
enum DeckMode { fx, loop, eq, cues, sampler, pitch }

const deckModeLabels = {
  DeckMode.fx: 'FX',
  DeckMode.loop: 'LOOP',
  DeckMode.eq: 'SMART EQ',
  DeckMode.cues: 'HOT CUES',
  DeckMode.sampler: 'SAMPLER',
  DeckMode.pitch: 'PITCH',
};

/// The panel for a deck mode, on a black card like the turntable's space.
class DeckModePanel extends StatelessWidget {
  final DeckId deckId;
  final DeckMode mode;

  const DeckModePanel({super.key, required this.deckId, required this.mode});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white10),
      ),
      child: switch (mode) {
        DeckMode.fx => _FxPage(deckId),
        DeckMode.loop => _LoopPage(deckId),
        DeckMode.eq => _EqPage(deckId),
        DeckMode.cues => _CuesPage(deckId),
        DeckMode.sampler => _SamplerPage(deckId),
        DeckMode.pitch => _PitchPage(deckId),
      },
    );
  }
}

/// A square-ish pad, lit in [color] when active.
class _Pad extends StatelessWidget {
  final String label;
  final String? sub;
  final Color color;
  final bool lit;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Gradient? gradient;

  const _Pad({
    required this.label,
    this.sub,
    required this.color,
    this.lit = false,
    required this.onTap,
    this.onLongPress,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final c = enabled ? color : DjColors.textDim.withValues(alpha: 0.4);
    return Padding(
      padding: const EdgeInsets.all(3),
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            color:
                gradient == null ? (lit ? c : const Color(0xFF111114)) : null,
            gradient: enabled ? gradient : null,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: lit ? c : Colors.white24),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: onTap,
            onLongPress: onLongPress,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: gradient != null
                                  ? Colors.black
                                  : (lit ? Colors.black : c))),
                      if (sub != null)
                        Text(sub!,
                            style: TextStyle(
                                fontSize: 10,
                                color:
                                    lit ? Colors.black87 : DjColors.textDim)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lays children out as an even grid that fills the space.
class _Grid extends StatelessWidget {
  final int columns;
  final List<Widget> children;

  const _Grid({required this.columns, required this.children});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += columns) {
      rows.add(Expanded(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var j = i; j < i + columns; j++)
              Expanded(
                  child: j < children.length ? children[j] : const SizedBox()),
          ],
        ),
      ));
    }
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}

// ---------------------------------------------------------------- LOOP --

class _LoopPage extends StatefulWidget {
  final DeckId deckId;
  const _LoopPage(this.deckId);

  @override
  State<_LoopPage> createState() => _LoopPageState();
}

class _LoopPageState extends State<_LoopPage> {
  /// Index into [loopSizes] of the size shown in the top row.
  int _size = loopSizes.indexOf(4.0);

  @override
  Widget build(BuildContext context) {
    final mixer = context.watch<MixerController>();
    final deck = mixer.deckFor(widget.deckId);
    final color = DjColors.forDeck(widget.deckId);
    final on = deck.currentTrack != null;
    final beatsKnown = on && deck.bpm > 0;
    final looping = deck.loopState == LoopState.looping;

    // While a loop runs, the arrows halve or double it.
    void step(int by) {
      setState(() => _size = (_size + by).clamp(0, loopSizes.length - 1));
      if (deck.autoLoopBeats != null) {
        mixer.autoLoop(widget.deckId, loopSizes[_size]);
      }
    }

    Widget sizePad(double beats) => _Pad(
          label: beatsLabel(beats),
          color: color,
          lit: deck.autoLoopBeats == beats,
          onTap: beatsKnown ? () => mixer.autoLoop(widget.deckId, beats) : null,
        );

    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                  child: _Pad(
                      label: '<',
                      color: Colors.white,
                      onTap: _size > 0 ? () => step(-1) : null)),
              Expanded(flex: 2, child: sizePad(loopSizes[_size])),
              Expanded(
                  child: _Pad(
                      label: '>',
                      color: Colors.white,
                      onTap:
                          _size < loopSizes.length - 1 ? () => step(1) : null)),
            ],
          ),
        ),
        Expanded(
          flex: 3,
          child: _Grid(columns: 2, children: [
            for (final b in const [8.0, 4.0, 1.0, 2.0, 0.5, 0.25]) sizePad(b),
          ]),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _Pad(
                  label: 'IN',
                  color: color,
                  lit: deck.loopState == LoopState.settingOut,
                  onTap: !on
                      ? null
                      : deck.loopState == LoopState.off || looping
                          ? () => looping
                              ? mixer.exitLoop(widget.deckId)
                              : mixer.loopButton(widget.deckId)
                          : null,
                ),
              ),
              Expanded(
                child: _Pad(
                  label: looping ? 'EXIT' : 'OUT',
                  color: color,
                  lit: looping,
                  onTap: deck.loopState == LoopState.settingOut
                      ? () => mixer.loopButton(widget.deckId)
                      : looping
                          ? () => mixer.exitLoop(widget.deckId)
                          : null,
                ),
              ),
            ],
          ),
        ),
        if (on && !beatsKnown)
          const Text("This song's beat wasn't found; use IN / OUT",
              style: TextStyle(fontSize: 10, color: DjColors.textDim)),
      ],
    );
  }
}

// ------------------------------------------------------------ SMART EQ --

/// A vertical fader with a label and a value readout; double-tap resets.
class _VFader extends StatelessWidget {
  final String label, readout;
  final double value, min, max, reset;
  final Color color;
  final ValueChanged<double>? onChanged;

  const _VFader({
    required this.label,
    required this.readout,
    required this.value,
    required this.min,
    required this.max,
    required this.reset,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: onChanged == null ? null : () => onChanged!(reset),
      child: Column(
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: DjColors.textDim)),
          Text(readout,
              style: TextStyle(
                  fontSize: 11,
                  color: onChanged == null ? Colors.white38 : color)),
          Expanded(
            child: RotatedBox(
              quarterTurns: 3,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 6,
                  activeTrackColor: color,
                  inactiveTrackColor: const Color(0xFF26262C),
                  thumbColor: Colors.white,
                  thumbShape: const _FaderCap(),
                  overlayShape: SliderComponentShape.noOverlay,
                ),
                child: Slider(
                  value: value.clamp(min, max),
                  min: min,
                  max: max,
                  onChanged: onChanged,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A flat fader cap, like a mixer's.
class _FaderCap extends SliderComponentShape {
  const _FaderCap();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(14, 28);

  @override
  void paint(PaintingContext context, Offset center,
      {required Animation<double> activationAnimation,
      required Animation<double> enableAnimation,
      required bool isDiscrete,
      required TextPainter labelPainter,
      required RenderBox parentBox,
      required SliderThemeData sliderTheme,
      required TextDirection textDirection,
      required double value,
      required double textScaleFactor,
      required Size sizeWithOverflow}) {
    final canvas = context.canvas;
    final r = RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: 12, height: 26),
        const Radius.circular(2));
    canvas.drawRRect(r, Paint()..color = const Color(0xFFDADAE0));
    canvas.drawLine(
        center.translate(0, -12),
        center.translate(0, 12),
        Paint()
          ..color = Colors.black54
          ..strokeWidth = 2);
  }
}

class _EqPage extends StatelessWidget {
  final DeckId deckId;
  const _EqPage(this.deckId);

  @override
  Widget build(BuildContext context) {
    final mixer = context.watch<MixerController>();
    final deck = mixer.deckFor(deckId);
    final color = DjColors.forDeck(deckId);
    final on = deck.currentTrack != null;
    String db(double v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)}dB';
    String gainDb(double g) => g < 0.01 ? '-inf' : db(20 * log(g) / ln10);
    Widget band(String label, double value, void Function(double) set) =>
        Expanded(
          child: _VFader(
            label: label,
            readout: db(value),
            value: value,
            min: eqMinDb,
            max: eqMaxDb,
            reset: 0,
            color: color,
            onChanged: on ? set : null,
          ),
        );
    return Row(
      children: [
        band('LOW', deck.eqLow, (v) => mixer.setEq(deckId, low: v)),
        band('MID', deck.eqMid, (v) => mixer.setEq(deckId, mid: v)),
        band('HIGH', deck.eqHigh, (v) => mixer.setEq(deckId, high: v)),
        Expanded(
          child: _VFader(
            label: 'GAIN',
            readout: gainDb(deck.trim),
            value: deck.trim,
            min: 0,
            max: maxTrim,
            reset: 1,
            color: Colors.white,
            onChanged: on ? (v) => mixer.setTrim(deckId, v) : null,
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ HOT CUES --

class _CuesPage extends StatelessWidget {
  final DeckId deckId;
  const _CuesPage(this.deckId);

  static const _colors = [
    Color(0xFFFF3B6B),
    Color(0xFF3BE07A),
    Color(0xFFFFC53B),
    Color(0xFFB45CFF),
  ];

  @override
  Widget build(BuildContext context) {
    final mixer = context.watch<MixerController>();
    final deck = mixer.deckFor(deckId);
    final on = deck.currentTrack != null;
    String clock(Duration d) =>
        '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
    return Column(
      children: [
        Expanded(
          child: _Grid(columns: 2, children: [
            for (var i = 0; i < hotCueCount; i++)
              _Pad(
                label: '${i + 1}',
                sub: deck.hotCues[i] == null
                    ? 'tap to set'
                    : clock(deck.hotCues[i]!),
                color: _colors[i],
                lit: deck.hotCues[i] != null,
                onTap: on ? () => mixer.hotCue(deckId, i) : null,
                onLongPress: deck.hotCues[i] == null
                    ? null
                    : () => mixer.clearHotCue(deckId, i),
              ),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text('Tap to save a spot, tap again to jump. Hold to clear.',
              style: TextStyle(fontSize: 10, color: DjColors.textDim)),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------- SAMPLER --

class _SamplerPage extends StatelessWidget {
  final DeckId deckId;
  const _SamplerPage(this.deckId);

  static const _gradients = [
    [Color(0xFF39D2FF), Color(0xFF2E7BFF)],
    [Color(0xFFFF8A3D), Color(0xFFFF3D7F)],
    [Color(0xFFF9F871), Color(0xFF7EE36B)],
    [Color(0xFF4DFFB0), Color(0xFF23C4F0)],
    [Color(0xFFFF5EDF), Color(0xFF8B5CFF)],
    [Color(0xFFFFD25E), Color(0xFFFF8A3D)],
  ];

  @override
  Widget build(BuildContext context) {
    final mixer = context.watch<MixerController>();
    return Row(
      children: [
        SizedBox(
          width: 44,
          child: _VFader(
            label: 'VOL',
            readout: '${(mixer.samplerVolume * 100).round()}',
            value: mixer.samplerVolume,
            min: 0,
            max: 1,
            reset: 0.8,
            color: Colors.white,
            onChanged: mixer.setSamplerVolume,
          ),
        ),
        Expanded(
          child: _Grid(columns: 2, children: [
            for (final (i, (label, _)) in samplePads.indexed)
              _Pad(
                label: label,
                color: Colors.white,
                gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _gradients[i % _gradients.length]),
                onTap: () => mixer.playSample(i),
              ),
          ]),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ FX --

class _FxPage extends StatefulWidget {
  final DeckId deckId;
  const _FxPage(this.deckId);

  @override
  State<_FxPage> createState() => _FxPageState();
}

class _FxPageState extends State<_FxPage> {
  /// The effect on the top pad (echo or flanger); the bottom pad is the
  /// filter.
  DeckFx _choice = DeckFx.echo;
  bool _fxLock = false, _filterLock = false;

  @override
  Widget build(BuildContext context) {
    final mixer = context.watch<MixerController>();
    final deck = mixer.deckFor(widget.deckId);
    final color = DjColors.forDeck(widget.deckId);
    final on = deck.currentTrack != null;
    final fxActive = deck.fx != DeckFx.none;

    void pickFx(int by) {
      setState(() =>
          _choice = _choice == DeckFx.echo ? DeckFx.flanger : DeckFx.echo);
      if (fxActive) mixer.setFx(widget.deckId, _choice);
    }

    return Column(
      children: [
        _FxHeader(
          title: _choice == DeckFx.echo ? 'ECHO' : 'FLANGER',
          onPrev: () => pickFx(-1),
          onNext: () => pickFx(1),
          locked: _fxLock,
          onLock: () {
            setState(() => _fxLock = !_fxLock);
            if (!_fxLock) mixer.setFx(widget.deckId, DeckFx.none);
          },
        ),
        Expanded(
          child: _XyPad(
            color: color,
            enabled: on,
            active: fxActive,
            point: Offset(deck.fxAmount, 1 - deck.fxParam),
            labels: _choice == DeckFx.echo
                ? const ('DRY', 'WET', 'LONG', 'SHORT')
                : const ('DRY', 'WET', 'FAST', 'SLOW'),
            onMove: (p) => mixer.setFx(widget.deckId, _choice,
                amount: p.dx, param: 1 - p.dy),
            onRelease: () {
              if (!_fxLock) mixer.setFx(widget.deckId, DeckFx.none);
            },
          ),
        ),
        const SizedBox(height: 6),
        _FxHeader(
          title: 'FILTER',
          locked: _filterLock,
          onLock: () {
            setState(() => _filterLock = !_filterLock);
            if (!_filterLock) mixer.setFilter(widget.deckId, 0);
          },
        ),
        Expanded(
          child: _XyPad(
            color: color,
            enabled: on,
            active: deck.filter.abs() > 0.02,
            point: Offset((deck.filter + 1) / 2, 0.5),
            labels: const ('LOW-PASS', 'HIGH-PASS', '', ''),
            onMove: (p) {
              // A dead zone in the middle so "off" is easy to find.
              var f = p.dx * 2 - 1;
              f = f.abs() < 0.08 ? 0 : f;
              mixer.setFilter(widget.deckId, f);
            },
            onRelease: () {
              if (!_filterLock) mixer.setFilter(widget.deckId, 0);
            },
          ),
        ),
      ],
    );
  }
}

class _FxHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onPrev, onNext;
  final bool locked;
  final VoidCallback onLock;

  const _FxHeader({
    required this.title,
    this.onPrev,
    this.onNext,
    required this.locked,
    required this.onLock,
  });

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, VoidCallback? onTap, {bool lit = false}) =>
        InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 30,
            height: 26,
            child: Icon(icon,
                size: 18,
                color: onTap == null
                    ? Colors.transparent
                    : (lit ? Colors.white : DjColors.textDim)),
          ),
        );
    return Container(
      height: 28,
      decoration: BoxDecoration(
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(4)),
      child: Row(
        children: [
          btn(Icons.chevron_left, onPrev),
          Expanded(
            child: Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, letterSpacing: 1)),
          ),
          btn(Icons.chevron_right, onNext),
          btn(locked ? Icons.lock : Icons.lock_open, onLock, lit: locked),
        ],
      ),
    );
  }
}

/// A touch pad: the effect runs while your finger is on it (or stays on
/// when locked). X is how much effect; Y is its setting.
class _XyPad extends StatelessWidget {
  final Color color;
  final bool enabled, active;
  final Offset point; // 0..1 each way
  final (String, String, String, String) labels; // left, right, top, bottom
  final ValueChanged<Offset> onMove;
  final VoidCallback onRelease;

  const _XyPad({
    required this.color,
    required this.enabled,
    required this.active,
    required this.point,
    required this.labels,
    required this.onMove,
    required this.onRelease,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      Offset norm(Offset p) => Offset((p.dx / box.maxWidth).clamp(0.0, 1.0),
          (p.dy / box.maxHeight).clamp(0.0, 1.0));
      const dim = TextStyle(fontSize: 9, color: DjColors.textDim);
      return Listener(
        onPointerDown: enabled ? (e) => onMove(norm(e.localPosition)) : null,
        onPointerMove: enabled ? (e) => onMove(norm(e.localPosition)) : null,
        onPointerUp: enabled ? (_) => onRelease() : null,
        onPointerCancel: enabled ? (_) => onRelease() : null,
        child: Container(
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF0E0E12),
            border: Border.all(color: active ? color : Colors.white24),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Stack(
            children: [
              // Grid lines.
              Positioned.fill(child: CustomPaint(painter: _GridPainter())),
              Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text(labels.$1, style: dim))),
              Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text(labels.$2, style: dim))),
              Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Text(labels.$3, style: dim))),
              Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Text(labels.$4, style: dim))),
              if (active)
                Positioned(
                  left: point.dx * box.maxWidth - 14,
                  top: point.dy * box.maxHeight - 14,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: 0.35),
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [BoxShadow(color: color, blurRadius: 12)],
                    ),
                  ),
                ),
              if (!enabled)
                const Center(
                    child: Text('Load a song first',
                        style: TextStyle(color: Colors.white38, fontSize: 11))),
            ],
          ),
        ),
      );
    });
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white.withValues(alpha: 0.05);
    for (var i = 1; i < 6; i++) {
      final x = size.width * i / 6, y = size.height * i / 6;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => false;
}

// --------------------------------------------------------------- PITCH --

class _PitchPage extends StatelessWidget {
  final DeckId deckId;
  const _PitchPage(this.deckId);

  @override
  Widget build(BuildContext context) {
    final mixer = context.watch<MixerController>();
    final deck = mixer.deckFor(deckId);
    final color = DjColors.forDeck(deckId);
    final percent = (deck.tempo - 1) * 100;
    void nudge(double by) => mixer.setTempo(deckId, deck.tempo + by);
    return Row(
      children: [
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('${percent >= 0 ? '+' : ''}${percent.toStringAsFixed(1)}%',
                  style: TextStyle(
                      color: color, fontSize: 26, fontWeight: FontWeight.bold)),
              if (deck.bpm > 0)
                Text('${deck.liveBpm.toStringAsFixed(1)} BPM',
                    style: const TextStyle(color: DjColors.textDim)),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: [
                  OutlinedButton(
                      onPressed: () => nudge(-0.001),
                      child: const Text('-0.1')),
                  OutlinedButton(
                      onPressed: () => nudge(0.001), child: const Text('+0.1')),
                  OutlinedButton(
                      onPressed: () => mixer.setTempo(deckId, 1),
                      child: const Text('RESET')),
                ],
              ),
              const SizedBox(height: 6),
              const Text('Changes speed and pitch, like a turntable',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10, color: DjColors.textDim)),
            ],
          ),
        ),
        SizedBox(
          width: 56,
          child: _VFader(
            label: 'PITCH',
            readout: '±${(maxTempoShift * 100).round()}%',
            // Up is slower, like a turntable's pitch fader.
            value: 2 - deck.tempo,
            min: 1 - maxTempoShift,
            max: 1 + maxTempoShift,
            reset: 1,
            color: color,
            onChanged: (v) => mixer.setTempo(deckId, 2 - v),
          ),
        ),
      ],
    );
  }
}
