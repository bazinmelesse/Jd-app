import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../models/track.dart';
import 'youtube_service.dart';
import 'engine/engine_bridge.dart';
import 'engine/local_song.dart';

enum DeckId { left, right }

/// Where a deck's loop is: off, waiting for the "out" point, or looping.
enum LoopState { off, settingOut, looping }

/// Tempo slider range: +/- 16%, a common DJ setting.
const double maxTempoShift = 0.16;

/// Deck effects (match DeckEngine.FX_* on the Android side).
enum DeckFx { none, echo, flanger }

/// EQ range in dB: a full "kill" down, a little boost up (like edjing).
const double eqMinDb = -26, eqMaxDb = 6;

/// Auto-loop sizes, in beats (the loop page shows six at a time).
const loopSizes = [1 / 8, 1 / 4, 1 / 2, 1.0, 2.0, 4.0, 8.0, 16.0, 32.0];

/// "1/4", "2", ... for a loop size in beats.
String beatsLabel(double beats) =>
    beats >= 1 ? '${beats.round()}' : '1/${(1 / beats).round()}';

/// Gain knob range (linear): silent .. +4 dB.
const double maxTrim = 1.58;

/// The sampler pads: label and bundled sound file.
const samplePads = [
  ('Air horn', 'air_horn.mp3'),
  ('Siren', 'siren.mp3'),
  ('Scratch', 'scratch_hit.mp3'),
  ('Laser', 'laser.mp3'),
  ('Riser', 'riser.mp3'),
  ('Rewind', 'rewind.mp3'),
];

/// Number of hot cue pads per deck.
const hotCueCount = 4;

/// The native DJ engine (android/.../engine): two decks whose songs are
/// decoded into memory, so they can play forwards or backwards at any speed
/// under a finger, like real vinyl.
const _engine = Engine();

/// One turntable/deck: the loaded track, its waveform, and its controls.
class Deck {
  final DeckId id;
  Track? currentTrack;
  double volume = 1.0; // 0.0 - 1.0, this deck's own channel volume
  double trim = 1.0; // the EQ page's GAIN fader, 0 .. maxTrim

  /// Headphone button: hear this deck in the right ear (split mode).
  bool headphones = false;

  /// Y axis of the FX pad, 0..1: echo time or flanger speed.
  double fxParam = 0.5;
  bool isLoading = false;
  bool isPlaying = false;

  /// Playback speed, 1.0 = normal. Like a real turntable, faster also
  /// means higher pitch.
  double tempo = 1.0;

  Duration duration = Duration.zero;

  /// Loudness peaks for drawing the waveform, [peaksPerSecond] per second.
  Float32List peaks = Float32List(0);

  /// Per peak: 0 = bassy .. 1 = bright, used to color the waveform.
  Float32List tones = Float32List(0);
  int peaksPerSecond = 100;

  /// Spot the CUE button jumps back to.
  Duration cuePoint = Duration.zero;

  LoopState loopState = LoopState.off;
  Duration _loopIn = Duration.zero;

  /// Size of the running auto-loop in beats, or null for none/manual.
  double? autoLoopBeats;

  /// Detected tempo of the song (0 = unknown) and where its first beat is.
  double bpm = 0;
  Duration firstBeat = Duration.zero;

  /// Tempo as heard right now, including the tempo slider.
  double get liveBpm => bpm * tempo;

  /// Hot cue points (null = empty pad).
  final List<Duration?> hotCues = List.filled(hotCueCount, null);

  double eqLow = 0, eqMid = 0, eqHigh = 0; // dB
  double filter = 0; // -1 low-pass .. 0 off .. +1 high-pass
  DeckFx fx = DeckFx.none;
  double fxAmount = 0.5;

  // Last position reported by the engine, and when; used to draw smoothly
  // between reports.
  Duration _reported = Duration.zero;
  Duration _reportedAt = Duration.zero;
  final Stopwatch _clock = Stopwatch()..start();

  Deck(this.id);

  int get _index => id == DeckId.left ? 0 : 1;
  Map<String, Object> _args([Map<String, Object>? more]) =>
      {'deck': _index, ...?more};

  /// Where the song is right now, estimated between engine reports so
  /// waveforms and the record move smoothly.
  Duration get position {
    if (!isPlaying) return _reported;
    final elapsed = _clock.elapsed - _reportedAt;
    final p = _reported + elapsed * tempo;
    return p > duration ? duration : p;
  }

  void _report(Duration p) {
    _reported = p;
    _reportedAt = _clock.elapsed;
  }

  /// Decodes the whole song into the engine. Only marks the track as loaded
  /// once that succeeded, so a failure doesn't leave a title on a silent deck.
  Future<void> loadFile(File file, Track track) async {
    _loaded(await _engine.invokeMapMethod('load', _args({'path': file.path})),
        track);
    await _engine.invokeMethod('tempo', _args({'tempo': tempo}));
  }

  /// Web version: decodes a song the user opened from their device.
  Future<void> loadLocal(Track track) async {
    _loaded(
        await _engine.invokeMapMethod(
            'loadLocal', _args({'id': track.localId})),
        track);
    await _engine.invokeMethod('tempo', _args({'tempo': tempo}));
  }

  void _loaded(Map<String, Object?>? result, Track track) {
    duration = Duration(milliseconds: (result!['durationMs'] as num).toInt());
    peaks = result['peaks'] as Float32List;
    peaksPerSecond = (result['peaksPerSecond'] as num).toInt();
    tones = result['tones'] as Float32List? ?? Float32List(peaks.length);
    bpm = (result['bpm'] as num).toDouble();
    firstBeat =
        Duration(microseconds: ((result['firstBeatMs'] as num) * 1000).round());
    currentTrack = track;
    isPlaying = false;
    cuePoint = Duration.zero;
    loopState = LoopState.off;
    autoLoopBeats = null;
    hotCues.fillRange(0, hotCueCount, null);
    _report(Duration.zero);
  }

  Future<void> play() async {
    isPlaying = true;
    _report(_reported);
    await _engine.invokeMethod('play', _args({'playing': true}));
  }

  Future<void> pause() async {
    isPlaying = false;
    await _engine.invokeMethod('play', _args({'playing': false}));
  }

  Future<void> seek(Duration to) async {
    final clamped =
        to < Duration.zero ? Duration.zero : (to > duration ? duration : to);
    _report(clamped);
    await _engine.invokeMethod('seek', _args({'ms': clamped.inMilliseconds}));
  }

  Future<void> setTempo(double value) async {
    _report(position);
    tempo = value.clamp(1 - maxTempoShift, 1 + maxTempoShift);
    await _engine.invokeMethod('tempo', _args({'tempo': tempo}));
  }

  Future<void> setGain(double gain) =>
      _engine.invokeMethod('gain', _args({'gain': gain}));

  /// SET: mark the current spot as the cue point (playing or not).
  void setCuePoint() => cuePoint = position;

  /// Jump to the cue point; keeps playing if the deck was playing.
  Future<void> jumpToCue() => seek(cuePoint);

  Future<void> setHeadphones(bool on) async {
    headphones = on;
    await _engine.invokeMethod('cue', _args({'on': on}));
  }

  /// Pitch bend (the + / - buttons): nudge the speed while held, to line
  /// up beats by ear. [direction] is +1, -1, or 0 to let go.
  Future<void> bend(int direction) async {
    _report(position);
    await _engine.invokeMethod(
        'tempo', _args({'tempo': tempo * (1 + 0.04 * direction)}));
  }

  /// Paused: mark the current spot as the cue point.
  /// Playing: jump back to the cue point and keep playing.
  Future<void> cue() async {
    if (isPlaying) {
      await seek(cuePoint);
    } else {
      cuePoint = position;
    }
  }

  /// One button for the whole loop: first press marks the start, second
  /// press marks the end and starts looping, third press exits the loop.
  Future<void> loopButton() async {
    switch (loopState) {
      case LoopState.off:
        _loopIn = position;
        loopState = LoopState.settingOut;
      case LoopState.settingOut:
        final out = position;
        if (out - _loopIn < const Duration(milliseconds: 100)) {
          loopState = LoopState.off; // too short to loop, start over
          return;
        }
        loopState = LoopState.looping;
        await _engine.invokeMethod(
            'loop',
            _args(
                {'inMs': _loopIn.inMilliseconds, 'outMs': out.inMilliseconds}));
        await seek(_loopIn);
      case LoopState.looping:
        await exitLoop();
    }
  }

  Future<void> exitLoop() async {
    loopState = LoopState.off;
    autoLoopBeats = null;
    await _engine.invokeMethod('loop', _args({'inMs': -1, 'outMs': -1}));
  }

  /// Length of one beat, or null if the tempo is unknown.
  Duration? get beatLength =>
      bpm > 0 ? Duration(microseconds: (60e6 / bpm).round()) : null;

  /// The beat (or, for short loops, the beat fraction) at or just before
  /// [at], so loops start on the beat.
  Duration _beatBefore(Duration at, [double grid = 1]) {
    final beat = beatLength! * grid;
    final n = ((at - firstBeat).inMicroseconds / beat.inMicroseconds).floor();
    final b = firstBeat + beat * n;
    return b < Duration.zero ? Duration.zero : b;
  }

  /// Loops [beats] beats starting from the current beat (edjing's auto
  /// loop). Tapping the running size again exits the loop.
  Future<void> autoLoop(double beats) async {
    if (autoLoopBeats == beats || beatLength == null) {
      await exitLoop();
      return;
    }
    final start = _beatBefore(position, min(beats, 1.0));
    final end = start + beatLength! * beats;
    _loopIn = start;
    autoLoopBeats = beats;
    loopState = LoopState.looping;
    await _engine.invokeMethod('loop',
        _args({'inMs': start.inMilliseconds, 'outMs': end.inMilliseconds}));
    if (position >= end) await seek(start);
  }

  /// Tap an empty pad to save the current spot; tap a saved pad to jump
  /// there (and keep playing); long-press to clear it.
  Future<void> hotCue(int pad) async {
    final saved = hotCues[pad];
    if (saved == null) {
      hotCues[pad] = position;
    } else {
      await seek(saved);
    }
  }

  void clearHotCue(int pad) => hotCues[pad] = null;

  Future<void> setEq({double? low, double? mid, double? high}) async {
    eqLow = (low ?? eqLow).clamp(eqMinDb, eqMaxDb);
    eqMid = (mid ?? eqMid).clamp(eqMinDb, eqMaxDb);
    eqHigh = (high ?? eqHigh).clamp(eqMinDb, eqMaxDb);
    await _engine.invokeMethod(
        'eq', _args({'low': eqLow, 'mid': eqMid, 'high': eqHigh}));
  }

  Future<void> setFilter(double amount) async {
    filter = amount.clamp(-1.0, 1.0);
    await _engine.invokeMethod('filter', _args({'amount': filter}));
  }

  /// [amount] is how much effect (the FX pad's X axis). [param] (the Y
  /// axis) sets the echo time, from 1/8 to 1 beat in musical steps, or the
  /// flanger's sweep speed.
  Future<void> setFx(DeckFx type, {double? amount, double? param}) async {
    fx = type;
    fxAmount = (amount ?? fxAmount).clamp(0.0, 1.0);
    fxParam = (param ?? fxParam).clamp(0.0, 1.0);
    final double ms;
    if (type == DeckFx.flanger) {
      ms = 8000 - 7000 * fxParam; // slow sweep at the bottom, fast at top
    } else {
      const steps = [1 / 8, 1 / 4, 1 / 2, 3 / 4, 1.0];
      final beat = bpm > 0 ? 60000 / (bpm * tempo) : 500.0;
      ms = beat * steps[(fxParam * (steps.length - 1)).round()];
    }
    await _engine.invokeMethod(
        'fx', _args({'type': type.index, 'amount': fxAmount, 'delayMs': ms}));
  }

  /// Matches this deck's tempo and beat timing to [master] (SYNC).
  Future<void> syncTo(Deck master) async {
    if (bpm <= 0 || master.bpm <= 0) return;
    // Match speed; allow double/half time (e.g. 70 vs 140 BPM).
    var target = master.liveBpm;
    while (target / bpm > 1.5) {
      target /= 2;
    }
    while (target / bpm < 0.67) {
      target *= 2;
    }
    await setTempo(target / bpm);
    // Line up the beats: move by the phase difference (at most half a beat).
    final myBeat = 60e6 / bpm, theirBeat = 60e6 / master.bpm;
    final myPhase = ((position - firstBeat).inMicroseconds % myBeat) / myBeat;
    final theirPhase =
        ((master.position - master.firstBeat).inMicroseconds % theirBeat) /
            theirBeat;
    var diff = theirPhase - myPhase;
    if (diff > 0.5) diff -= 1;
    if (diff < -0.5) diff += 1;
    await seek(position + Duration(microseconds: (diff * myBeat).round()));
  }

  // ---- Scratching: the engine's playhead chases the finger. ----

  /// Finger touches the record: it stops under the hand.
  void scratchStart() => _engine.invokeMethod('scratchStart', _args());

  /// Finger moved the record by [delta] of song time (negative = back).
  void scratchMove(double deltaMs) {
    _report(_reported + Duration(microseconds: (deltaMs * 1000).round()));
    _engine.invokeMethod('scratchMove', _args({'deltaMs': deltaMs}));
  }

  /// Finger lets go: the motor takes over again if the deck is playing.
  void scratchEnd() => _engine.invokeMethod('scratchEnd', _args());
}

/// Coordinates both decks plus the crossfader between them.
/// Exposed via Provider so any widget can read/control mixer state.
class MixerController extends ChangeNotifier {
  final Deck left = Deck(DeckId.left);
  final Deck right = Deck(DeckId.right);
  final YoutubeService youtube = YoutubeService();

  /// 0.0 = fully left deck, 1.0 = fully right deck, 0.5 = even mix.
  double _crossfade = 0.5;
  double get crossfade => _crossfade;

  /// Last load error, shown to the user once and then cleared.
  String? lastError;

  Timer? _poll;

  MixerController() {
    // Ask the engine where both decks are ~30 times a second.
    _poll = Timer.periodic(const Duration(milliseconds: 33), (_) => _sync());
  }

  bool _syncing = false;
  Future<void> _sync() async {
    if (_syncing || (left.currentTrack == null && right.currentTrack == null)) {
      return;
    }
    _syncing = true;
    try {
      final s = await _engine.invokeListMethod('state');
      if (s == null) return;
      var changed = false;
      for (final (i, deck) in [left, right].indexed) {
        deck._report(Duration(milliseconds: (s[i] as num).toInt()));
        final playing = s[2 + i] as bool;
        if (playing != deck.isPlaying) {
          deck.isPlaying = playing; // e.g. the song reached its end
          changed = true;
        }
      }
      if (changed) notifyListeners();
    } on MissingPluginException {
      _poll?.cancel(); // no native engine (e.g. web preview)
    } finally {
      _syncing = false;
    }
  }

  Deck deckFor(DeckId id) => id == DeckId.left ? left : right;

  Future<void> loadTrackOnDeck(DeckId id, Track track) async {
    final deck = deckFor(id);
    deck.isLoading = true;
    notifyListeners(); // reflect isLoading = true immediately
    try {
      // Save the song on the device, then decode it into the engine.
      if (track.isLocal) {
        await deck.loadLocal(track);
      } else {
        final file =
            await youtube.downloadAudio(track.videoId, await _cacheFolder());
        await deck.loadFile(file, track);
      }
      _applyCrossfade();
    } catch (e) {
      lastError = 'Couldn\'t load "${track.title}": $e';
    } finally {
      deck.isLoading = false;
      notifyListeners();
    }
  }

  /// Saved songs live in the app's cache folder; only the most recent
  /// [_maxCachedSongs] are kept so storage doesn't fill up.
  static const _maxCachedSongs = 15;

  Future<Directory> _cacheFolder() async {
    final folder = Directory('${(await getTemporaryDirectory()).path}/decks');
    await folder.create(recursive: true);
    final files = folder.listSync().whereType<File>().toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    for (final old in files.skip(_maxCachedSongs)) {
      // Never delete a file a deck is currently playing.
      final inUse = [left, right].any((d) =>
          d.currentTrack != null && old.path.contains(d.currentTrack!.videoId));
      if (!inUse) old.deleteSync();
    }
    return folder;
  }

  Future<void> togglePlay(DeckId id) async {
    final deck = deckFor(id);
    if (deck.isPlaying) {
      await deck.pause();
    } else {
      await deck.play();
    }
    notifyListeners();
  }

  Future<void> setTempo(DeckId id, double value) async {
    await deckFor(id).setTempo(value);
    notifyListeners();
  }

  Future<void> cue(DeckId id) async {
    await deckFor(id).cue();
    notifyListeners();
  }

  Future<void> autoLoop(DeckId id, double beats) async {
    await deckFor(id).autoLoop(beats);
    notifyListeners();
  }

  Future<void> hotCue(DeckId id, int pad) async {
    await deckFor(id).hotCue(pad);
    notifyListeners();
  }

  void clearHotCue(DeckId id, int pad) {
    deckFor(id).clearHotCue(pad);
    notifyListeners();
  }

  Future<void> setEq(DeckId id,
      {double? low, double? mid, double? high}) async {
    final f = deckFor(id).setEq(low: low, mid: mid, high: high);
    notifyListeners();
    await f;
  }

  Future<void> setFilter(DeckId id, double amount) async {
    final f = deckFor(id).setFilter(amount);
    notifyListeners();
    await f;
  }

  Future<void> setFx(DeckId id, DeckFx fx,
      {double? amount, double? param}) async {
    final f = deckFor(id).setFx(fx, amount: amount, param: param);
    notifyListeners();
    await f;
  }

  /// SYNC: match this deck to the other one.
  Future<void> sync(DeckId id) async {
    final other = id == DeckId.left ? right : left;
    await deckFor(id).syncTo(other);
    notifyListeners();
  }

  Future<void> loopButton(DeckId id) async {
    await deckFor(id).loopButton();
    notifyListeners();
  }

  Future<void> exitLoop(DeckId id) async {
    await deckFor(id).exitLoop();
    notifyListeners();
  }

  Future<void> seek(DeckId id, Duration to) async {
    await deckFor(id).seek(to);
    notifyListeners();
  }

  void setCrossfade(double value) {
    _crossfade = value.clamp(0.0, 1.0);
    _applyCrossfade();
    notifyListeners();
  }

  /// Equal-power crossfade curve so the perceived loudness stays roughly
  /// constant as you sweep the fader, rather than dipping in the middle.
  void _applyCrossfade() {
    final leftGain = cos(_crossfade * pi / 2);
    final rightGain = sin(_crossfade * pi / 2);
    left.setGain(leftGain * left.volume * left.trim).catchError((_) {});
    right.setGain(rightGain * right.volume * right.trim).catchError((_) {});
  }

  void setDeckVolume(DeckId id, double volume) {
    deckFor(id).volume = volume.clamp(0.0, 1.0);
    _applyCrossfade();
    notifyListeners();
  }

  /// The EQ page's GAIN fader.
  void setTrim(DeckId id, double trim) {
    deckFor(id).trim = trim.clamp(0.0, maxTrim);
    _applyCrossfade();
    notifyListeners();
  }

  void setCuePoint(DeckId id) {
    deckFor(id).setCuePoint();
    notifyListeners();
  }

  Future<void> jumpToCue(DeckId id) async {
    await deckFor(id).jumpToCue();
    notifyListeners();
  }

  Future<void> toggleHeadphones(DeckId id) async {
    final deck = deckFor(id);
    await deck.setHeadphones(!deck.headphones);
    notifyListeners();
  }

  Future<void> bend(DeckId id, int direction) => deckFor(id).bend(direction);

  /// The center SYNC button: the deck the crowd hears less follows the
  /// other one.
  Future<void> syncQuiet() async {
    final follower = _crossfade > 0.5 ? DeckId.left : DeckId.right;
    await sync(follower);
  }

  // ---- Crossfader moves (the arrow buttons and automix) ----

  Timer? _fade;

  /// Slides the crossfader to [target] over [over].
  void glideCrossfade(double target, Duration over) {
    _fade?.cancel();
    final from = _crossfade;
    final watch = Stopwatch()..start();
    _fade = Timer.periodic(const Duration(milliseconds: 40), (t) {
      final k =
          (watch.elapsedMilliseconds / over.inMilliseconds).clamp(0.0, 1.0);
      _crossfade = from + (target - from) * k;
      _applyCrossfade();
      notifyListeners();
      if (k >= 1) t.cancel();
    });
  }

  // ---- Sampler pads (played by the native engine, over the mix) ----

  Future<void>? _samplesLoaded;
  double samplerVolume = 0.8;

  /// Copies the bundled sounds out of the app package (the decoder needs
  /// real files) and loads them into the engine, once.
  Future<void> _loadSamples() async {
    if (isWebEngine) {
      for (final (i, (_, file)) in samplePads.indexed) {
        await _engine.invokeMethod(
            'sampleLoadUrl', {'slot': i, 'url': 'assets/assets/sounds/$file'});
      }
      await _engine.invokeMethod('sampleVolume', {'volume': samplerVolume});
      return;
    }
    final folder = Directory('${(await getTemporaryDirectory()).path}/samples');
    await folder.create(recursive: true);
    for (final (i, (_, file)) in samplePads.indexed) {
      final data = await rootBundle.load('assets/sounds/$file');
      final out = File('${folder.path}/$file');
      await out.writeAsBytes(data.buffer.asUint8List(), flush: true);
      await _engine.invokeMethod('sampleLoad', {'slot': i, 'path': out.path});
    }
    await _engine.invokeMethod('sampleVolume', {'volume': samplerVolume});
  }

  Future<void> playSample(int pad) async {
    try {
      await (_samplesLoaded ??= _loadSamples());
      await _engine.invokeMethod('sampleTrigger', {'slot': pad});
    } catch (e) {
      _samplesLoaded = null; // try again next tap
      lastError = 'Sampler: $e';
      notifyListeners();
    }
  }

  void setSamplerVolume(double v) {
    samplerVolume = v.clamp(0.0, 1.0);
    _engine.invokeMethod(
        'sampleVolume', {'volume': samplerVolume}).catchError((_) {});
    notifyListeners();
  }

  // ---- Automix: plays a list of songs, mixing each into the next ----

  bool get automixOn => _automixTimer != null;
  List<Track> _automixQueue = [];
  int _automixNext = 0;
  Timer? _automixTimer;
  bool _mixing = false;

  /// How long each automatic blend lasts.
  static const automixBlend = Duration(seconds: 10);

  /// Starts automix on [songs]. Whatever is playing now finishes first.
  Future<void> startAutomix(List<Track> songs) async {
    if (songs.isEmpty) return;
    _automixQueue = List.of(songs);
    _automixNext = 0;
    _mixing = false;
    _automixTimer?.cancel();
    _automixTimer = Timer.periodic(
        const Duration(milliseconds: 250), (_) => _automixTick());
    notifyListeners();
    final playing = [left, right].where((d) => d.isPlaying).toList();
    if (playing.isEmpty) {
      // Nothing playing: start the first song on deck A, full left.
      await loadTrackOnDeck(DeckId.left, _automixQueue[_automixNext++]);
      if (!automixOn || left.currentTrack == null) return;
      setCrossfade(0);
      await togglePlay(DeckId.left);
    }
    await _preloadNext();
  }

  void stopAutomix() {
    _automixTimer?.cancel();
    _automixTimer = null;
    notifyListeners();
  }

  /// The deck the crowd is hearing.
  Deck get _onAir => _crossfade <= 0.5 ? left : right;
  Deck get _offAir => _crossfade <= 0.5 ? right : left;

  Future<void> _preloadNext() async {
    if (!automixOn) return;
    if (_automixNext >= _automixQueue.length) return;
    await loadTrackOnDeck(_offAir.id, _automixQueue[_automixNext++]);
  }

  Future<void> _automixTick() async {
    if (_mixing) return;
    final on = _onAir, off = _offAir;
    if (!on.isPlaying || on.duration == Duration.zero) {
      // The song ended (or was stopped) without a mix: start the next one.
      if (on.currentTrack != null &&
          !on.isPlaying &&
          off.currentTrack != null &&
          !off.isLoading &&
          on.position >= on.duration - const Duration(seconds: 1)) {
        await _blendInto(off, quick: true);
      } else if (off.currentTrack == null &&
          _automixNext >= _automixQueue.length) {
        stopAutomix(); // nothing left to play
      }
      return;
    }
    final remaining = on.duration - on.position;
    if (remaining <= automixBlend + const Duration(seconds: 1) &&
        off.currentTrack != null &&
        !off.isLoading &&
        !off.isPlaying) {
      await _blendInto(off);
    } else if (remaining <= Duration.zero && off.currentTrack == null) {
      stopAutomix();
    }
  }

  Future<void> _blendInto(Deck next, {bool quick = false}) async {
    _mixing = true;
    final prev = next.id == DeckId.left ? right : left;
    try {
      // Skip a silent intro, match the tempo and beats, then fade across.
      await next.seek(next.firstBeat);
      next.cuePoint = next.firstBeat;
      await next.play();
      if (prev.isPlaying) await next.syncTo(prev);
      notifyListeners();
      final target = next.id == DeckId.left ? 0.0 : 1.0;
      final blend = quick ? const Duration(milliseconds: 500) : automixBlend;
      glideCrossfade(target, blend);
      await Future<void>.delayed(blend + const Duration(milliseconds: 200));
      if (!automixOn) return;
      await prev.pause();
      notifyListeners();
      await _preloadNext();
    } finally {
      _mixing = false;
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _fade?.cancel();
    _automixTimer?.cancel();
    youtube.dispose();
    super.dispose();
  }
}
