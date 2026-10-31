import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/audio_service.dart';
import '../theme/dj_colors.dart';
import 'deck_tools.dart';
import 'turntable_widget.dart';
import 'waveform.dart';

String _clock(Duration d) {
  final m = d.inMinutes;
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// Dark, slightly raised button used all over the DJ screen.
class DjButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool lit;
  final Color color;

  const DjButton({
    super.key,
    required this.child,
    required this.onTap,
    this.lit = false,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: lit ? color.withValues(alpha: 0.18) : DjColors.button,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side:
            BorderSide(color: lit ? color : Colors.black, width: lit ? 1.5 : 1),
      ),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Center(
          child: DefaultTextStyle.merge(
            style: TextStyle(
              color: !enabled
                  ? Colors.white24
                  : (lit ? color : const Color(0xFFB4B4BE)),
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
              fontSize: 12,
            ),
            child: IconTheme.merge(
              data: IconThemeData(
                  color:
                      !enabled ? Colors.white24 : (lit ? color : Colors.white)),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The big tempo readout at each top corner, with the PITCH button below.
class DeckBpmBox extends StatelessWidget {
  final DeckId deckId;
  final bool pitchOpen;
  final VoidCallback onPitch;

  const DeckBpmBox(
      {super.key,
      required this.deckId,
      required this.pitchOpen,
      required this.onPitch});

  @override
  Widget build(BuildContext context) {
    final deck = context.watch<MixerController>().deckFor(deckId);
    final color = DjColors.forDeck(deckId);
    return Column(
      children: [
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(deck.bpm > 0 ? deck.liveBpm.toStringAsFixed(1) : '--',
                    style: TextStyle(
                        color: color,
                        fontSize: 26,
                        fontWeight: FontWeight.w400)),
                const Text('BPM',
                    style: TextStyle(
                        color: Colors.white38, fontSize: 13, letterSpacing: 2)),
              ],
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: DjButton(
              lit: pitchOpen,
              color: color,
              onTap: onPitch,
              child: const Text('PITCH'),
            ),
          ),
        ),
      ],
    );
  }
}

/// A deck's title line (title and remaining time) over its whole-song
/// waveform.
class DeckHeader extends StatelessWidget {
  final DeckId deckId;

  const DeckHeader({super.key, required this.deckId});

  @override
  Widget build(BuildContext context) {
    final deck = context.watch<MixerController>().deckFor(deckId);
    final color = DjColors.forDeck(deckId);
    final track = deck.currentTrack;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(6)),
              child: Text(DjColors.letter(deckId),
                  style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w900,
                      fontSize: 11)),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                track == null
                    ? 'No song loaded'
                    : '${track.title}${track.author.isEmpty ? '' : ' (${track.author})'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontSize: 12),
              ),
            ),
            DeckFrameBuilder(
              deck: deck,
              builder: (context, position) => Text(
                track == null ? '' : _clock(deck.duration - position),
                style: TextStyle(color: color, fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Expanded(child: OverviewWaveform(deckId: deckId)),
      ],
    );
  }
}

/// FX / LOOP / SMART EQ / HOT CUES buttons for one deck, in a row (tablets)
/// or a column at the screen edge (short phone screens).
class DeckModeButtons extends StatelessWidget {
  final DeckId deckId;
  final DeckMode? open;
  final ValueChanged<DeckMode?> onChanged;
  final Axis direction;

  const DeckModeButtons({
    super.key,
    required this.deckId,
    required this.open,
    required this.onChanged,
    this.direction = Axis.horizontal,
  });

  @override
  Widget build(BuildContext context) {
    final color = DjColors.forDeck(deckId);
    const modes = [DeckMode.fx, DeckMode.loop, DeckMode.eq, DeckMode.cues];
    final buttons = [
      for (final m in modes)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: DjButton(
              lit: open == m,
              color: color,
              onTap: () => onChanged(open == m ? null : m),
              child: Text(
                  direction == Axis.vertical
                      ? deckModeLabels[m]!.replaceAll(' ', '\n')
                      : deckModeLabels[m]!,
                  textAlign: TextAlign.center),
            ),
          ),
        ),
    ];
    return direction == Axis.horizontal
        ? Row(children: buttons)
        : Column(children: buttons);
  }
}

/// The deck's main space: the turntable, or the open mode's panel.
class DeckArea extends StatelessWidget {
  final DeckId deckId;
  final DeckMode? mode;
  final VoidCallback onLoadTrackPressed;

  const DeckArea({
    super.key,
    required this.deckId,
    required this.mode,
    required this.onLoadTrackPressed,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      child: mode == null
          ? TurntableWidget(
              key: const ValueKey('turntable'),
              deckId: deckId,
              onLoadTrackPressed: onLoadTrackPressed,
            )
          : DeckModePanel(key: ValueKey(mode), deckId: deckId, mode: mode!),
    );
  }
}

/// The middle of the mixer: load buttons, channel faders, headphone cue
/// buttons, AUTOMIX and SYNC.
class CenterStrip extends StatelessWidget {
  final void Function(DeckId) onLoad;
  final VoidCallback onAutomix;

  const CenterStrip({super.key, required this.onLoad, required this.onAutomix});

  @override
  Widget build(BuildContext context) {
    final mixer = context.watch<MixerController>();
    return LayoutBuilder(
        builder: (context, box) => _build(context, mixer, box.maxHeight < 340));
  }

  Widget _build(BuildContext context, MixerController mixer, bool compact) {
    final unit = compact ? 30.0 : 38.0;
    Widget loadButton(DeckId id) {
      final color = DjColors.forDeck(id);
      final deck = mixer.deckFor(id);
      return Tooltip(
        message: 'Load a song on deck ${DjColors.letter(id)}',
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => onLoad(id),
          child: Container(
            width: unit + 6,
            height: unit + 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF15151A),
              border: Border.all(color: color, width: 2.5),
              boxShadow: [
                if (deck.currentTrack != null)
                  BoxShadow(
                      color: color.withValues(alpha: 0.5), blurRadius: 10),
              ],
            ),
            child: Icon(Icons.queue_music, color: color, size: unit * 0.55),
          ),
        ),
      );
    }

    Widget headphones(DeckId id) {
      final deck = mixer.deckFor(id);
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: DjButton(
            lit: deck.headphones,
            color: DjColors.forDeck(id),
            onTap: deck.currentTrack == null
                ? null
                : () {
                    mixer.toggleHeadphones(id);
                    if (!deck.headphones) {
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(const SnackBar(
                          duration: Duration(seconds: 4),
                          content: Text(
                              'Headphone cue: plug in headphones. The left ear '
                              'plays the mix, the right ear plays this deck.'),
                        ));
                    }
                  },
            child: const Icon(Icons.headphones, size: 18),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
      decoration: BoxDecoration(
        color: DjColors.panel,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [loadButton(DeckId.left), loadButton(DeckId.right)],
          ),
          const SizedBox(height: 6),
          const Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ChannelFader(deckId: DeckId.left),
                ChannelFader(deckId: DeckId.right),
              ],
            ),
          ),
          SizedBox(
            height: unit,
            child: Row(children: [
              headphones(DeckId.left),
              headphones(DeckId.right),
            ]),
          ),
          const SizedBox(height: 4),
          // Short screens put AUTOMIX and SYNC side by side.
          Flex(
            direction: compact ? Axis.horizontal : Axis.vertical,
            children: [
              Flexible(
                fit: FlexFit.tight,
                flex: compact ? 3 : 0,
                child: SizedBox(
                  height: unit,
                  width: double.infinity,
                  child: DjButton(
                    lit: mixer.automixOn,
                    color: const Color(0xFF3BE07A),
                    onTap: onAutomix,
                    child: const Text('AUTOMIX'),
                  ),
                ),
              ),
              const SizedBox(width: 4, height: 4),
              Flexible(
                fit: FlexFit.tight,
                flex: compact ? 2 : 0,
                child: SizedBox(
                  height: compact ? unit : unit + 6,
                  width: double.infinity,
                  child: DjButton(
                    onTap: mixer.left.bpm > 0 && mixer.right.bpm > 0
                        ? mixer.syncQuiet
                        : null,
                    child: const Text('SYNC'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A channel volume fader in the deck's color, vertical.
class ChannelFader extends StatelessWidget {
  final DeckId deckId;

  const ChannelFader({super.key, required this.deckId});

  @override
  Widget build(BuildContext context) {
    final mixer = context.watch<MixerController>();
    final color = DjColors.forDeck(deckId);
    return RotatedBox(
      quarterTurns: 3,
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 5,
          activeTrackColor: color,
          inactiveTrackColor: const Color(0xFF2A2A30),
          thumbColor: Colors.white,
          overlayColor: color.withValues(alpha: 0.15),
          thumbShape: const _WideCap(),
        ),
        child: Slider(
          value: mixer.deckFor(deckId).volume,
          onChanged: (v) => mixer.setDeckVolume(deckId, v),
        ),
      ),
    );
  }
}

/// A wide fader cap (drawn rotated, so it shows as a horizontal bar).
class _WideCap extends SliderComponentShape {
  const _WideCap();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(18, 50);

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
        Rect.fromCenter(center: center, width: 16, height: 48),
        const Radius.circular(2));
    canvas.drawRRect(
        r.shift(const Offset(2, 0)), Paint()..color = Colors.black54);
    canvas.drawRRect(r, Paint()..color = const Color(0xFFE6E6EC));
    canvas.drawLine(
        center.translate(0, -22),
        center.translate(0, 22),
        Paint()
          ..color = Colors.black87
          ..strokeWidth = 2);
  }
}

/// A deck's bottom controls: PLAY, then SET (mark the cue point) joined to
/// the jump-to-cue button.
class DeckTransport extends StatelessWidget {
  final DeckId deckId;
  final bool mirrored;

  const DeckTransport({super.key, required this.deckId, this.mirrored = false});

  @override
  Widget build(BuildContext context) {
    final mixer = context.watch<MixerController>();
    final deck = mixer.deckFor(deckId);
    final color = DjColors.forDeck(deckId);
    final loaded = deck.currentTrack != null;
    final play = AspectRatio(
      aspectRatio: 1.3,
      child: DjButton(
        lit: deck.isPlaying,
        color: color,
        onTap: loaded ? () => mixer.togglePlay(deckId) : null,
        child: Icon(deck.isPlaying ? Icons.pause : Icons.play_arrow,
            size: 30, color: loaded ? color : null),
      ),
    );
    final cue = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: 1.6,
          child: DjButton(
            onTap: loaded ? () => mixer.setCuePoint(deckId) : null,
            child: Text('SET',
                style: TextStyle(
                    color: loaded ? color : null,
                    fontSize: 16,
                    letterSpacing: 2)),
          ),
        ),
        const SizedBox(width: 2),
        AspectRatio(
          aspectRatio: 1.6,
          child: DjButton(
            onTap: loaded ? () => mixer.jumpToCue(deckId) : null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_forward,
                    size: 18, color: loaded ? color : null),
                const SizedBox(width: 4),
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: loaded ? const Color(0xFFFF2D2D) : Colors.white24,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
    final children = [play, const SizedBox(width: 10), cue];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: mirrored ? children.reversed.toList() : children,
    );
  }
}

/// The crossfader, with arrow buttons that slide it all the way across.
class CrossfaderBar extends StatelessWidget {
  const CrossfaderBar({super.key});

  @override
  Widget build(BuildContext context) {
    final mixer = context.watch<MixerController>();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: DjColors.panel,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.black),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Slide to deck A',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.arrow_left, color: DjColors.deckA),
            onPressed: () =>
                mixer.glideCrossfade(0, const Duration(seconds: 2)),
          ),
          Expanded(
            child: GestureDetector(
              // Double-tap to snap back to the middle.
              onDoubleTap: () => mixer.setCrossfade(0.5),
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  activeTrackColor: Colors.white24,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: Colors.white,
                  overlayColor: Colors.white10,
                  thumbShape: const _CrossCap(),
                  tickMarkShape: SliderTickMarkShape.noTickMark,
                ),
                child: Slider(
                  value: mixer.crossfade,
                  onChanged: mixer.setCrossfade,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Slide to deck B',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.arrow_right, color: DjColors.deckB),
            onPressed: () =>
                mixer.glideCrossfade(1, const Duration(seconds: 2)),
          ),
        ],
      ),
    );
  }
}

class _CrossCap extends SliderComponentShape {
  const _CrossCap();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(20, 40);

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
        Rect.fromCenter(center: center, width: 18, height: 38),
        const Radius.circular(2));
    canvas.drawRRect(r, Paint()..color = const Color(0xFFE6E6EC));
    canvas.drawLine(
        center.translate(0, -17),
        center.translate(0, 17),
        Paint()
          ..color = Colors.black87
          ..strokeWidth = 2);
  }
}
