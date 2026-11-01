import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../models/track.dart';
import '../services/audio_service.dart';
import '../services/library_service.dart';
import '../theme/dj_colors.dart';
import '../widgets/deck_panel.dart';
import '../widgets/deck_tools.dart';
import '../widgets/track_search_sheet.dart';
import '../widgets/track_thumb.dart';
import '../widgets/waveform.dart';
import '../services/engine/engine_bridge.dart';
import 'device_music_screen.dart';

/// DJ Mode: a full-screen, sideways two-deck mixer laid out like the big
/// DJ apps. Waveforms and tempo across the top; each deck's mode buttons,
/// turntable (or open panel) at the sides; the mixer in the middle; play,
/// cue, sampler and crossfader along the bottom.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// What each deck shows instead of its turntable (null = turntable).
  final Map<DeckId, DeckMode?> _modes = {DeckId.left: null, DeckId.right: null};

  void _setMode(DeckId id, DeckMode? mode) => setState(() => _modes[id] = mode);

  void _toggleMode(DeckId id, DeckMode mode) =>
      _setMode(id, _modes[id] == mode ? null : mode);

  void _showMessage(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void _openSearch(DeckId deck) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => TrackSearchSheet(targetDeck: deck),
    );
  }

  /// MENU: the way back to the other tabs while DJ Mode is full screen.
  void _openMenu() {
    final tabs = context.read<AppTabController>();
    showModalBottomSheet(
      context: context,
      builder: (sheet) => SafeArea(
        child: Wrap(
          children: [
            for (final (tab, icon, label) in [
              (AppTab.stream, Icons.play_circle, 'Stream'),
              (AppTab.karaoke, Icons.mic, 'Karaoke'),
              (AppTab.library, Icons.library_music, 'Library'),
            ])
              ListTile(
                leading: Icon(icon),
                title: Text(label),
                onTap: () {
                  Navigator.pop(sheet);
                  tabs.value = tab.index;
                },
              ),
          ],
        ),
      ),
    );
  }

  /// AUTOMIX: pick a playlist (or recent songs) and the app mixes through
  /// it on its own. Tapping it while it runs stops it.
  void _automix() {
    final mixer = context.read<MixerController>();
    if (mixer.automixOn) {
      mixer.stopAutomix();
      _showMessage('Automix off');
      return;
    }
    final library = context.read<LibraryController>();
    final device = context.read<DeviceSongs>();
    final sources = <(String, List<Track>)>[
      if (isWebEngine && device.songs.isNotEmpty)
        ('Songs from this device', List.of(device.songs)),
      for (final p in library.playlists)
        if (p.tracks.isNotEmpty) (p.name, p.tracks),
      if (library.recentTracks.isNotEmpty)
        ('Recently played', library.recentTracks),
    ];
    if (sources.isEmpty && !isWebEngine) {
      _showMessage(
          'Automix plays a playlist: make one in the Library tab first');
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8),
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(
                title: Text('Automix',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle:
                    Text('Pick what to play. Each song blends into the next, '
                        'with tempo and beats matched.'),
              ),
              if (isWebEngine)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: OpenSongsButton(
                    label: 'Pick songs to mix',
                    onPicked: (picked) {
                      if (picked.isEmpty) return;
                      Navigator.pop(sheet);
                      mixer.startAutomix(picked);
                    },
                  ),
                ),
              for (final (name, songs) in sources)
                ListTile(
                  leading: TrackThumb(songs.first.thumbnailUrl, width: 56),
                  title: Text(name),
                  subtitle: Text('${songs.length} songs'),
                  onTap: () {
                    Navigator.pop(sheet);
                    mixer.startAutomix(songs);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mixer = context.watch<MixerController>();

    // Tell the user when something fails instead of failing silently.
    final error = mixer.lastError;
    if (error != null) {
      mixer.lastError = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _showMessage(error));
    }

    return Scaffold(
      backgroundColor: DjColors.djBackground,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            // Short screens (phones on their side) put the mode buttons in
            // a column at each edge to save height.
            final short = box.maxHeight < 560;
            final topHeight = (box.maxHeight * 0.2).clamp(70.0, 170.0);
            final bottomHeight = (box.maxHeight * 0.1).clamp(44.0, 70.0);
            final centerWidth = (box.maxWidth * 0.14).clamp(120.0, 180.0);
            return Column(
              children: [
                SizedBox(height: topHeight, child: _top(short)),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _deckSide(DeckId.left, short)),
                        const SizedBox(width: 6),
                        SizedBox(
                          width: centerWidth,
                          child: CenterStrip(
                              onLoad: _openSearch, onAutomix: _automix),
                        ),
                        const SizedBox(width: 6),
                        Expanded(child: _deckSide(DeckId.right, short)),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  height: bottomHeight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(6, 2, 6, 6),
                    child: _bottom(centerWidth),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _top(bool short) {
    return Container(
      color: Colors.black,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 84,
            child: DeckBpmBox(
              deckId: DeckId.left,
              pitchOpen: _modes[DeckId.left] == DeckMode.pitch,
              onPitch: () => _toggleMode(DeckId.left, DeckMode.pitch),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                SizedBox(
                  height: short ? 30 : 38,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Expanded(child: DeckHeader(deckId: DeckId.left)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Center(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF2A2AA8),
                              visualDensity: VisualDensity.compact,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 18),
                              shape: const StadiumBorder(),
                            ),
                            onPressed: _openMenu,
                            child: const Text('MENU',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white)),
                          ),
                        ),
                      ),
                      const Expanded(child: DeckHeader(deckId: DeckId.right)),
                    ],
                  ),
                ),
                const Expanded(child: CenterWaveform()),
              ],
            ),
          ),
          SizedBox(
            width: 84,
            child: DeckBpmBox(
              deckId: DeckId.right,
              pitchOpen: _modes[DeckId.right] == DeckMode.pitch,
              onPitch: () => _toggleMode(DeckId.right, DeckMode.pitch),
            ),
          ),
        ],
      ),
    );
  }

  Widget _deckSide(DeckId id, bool short) {
    final area = DeckArea(
      deckId: id,
      mode: _modes[id],
      onLoadTrackPressed: () => _openSearch(id),
    );
    final buttons = DeckModeButtons(
      deckId: id,
      open: _modes[id],
      onChanged: (m) => _setMode(id, m),
      direction: short ? Axis.vertical : Axis.horizontal,
    );
    if (short) {
      final children = [
        SizedBox(width: 70, child: buttons),
        const SizedBox(width: 6),
        Expanded(child: area),
      ];
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: id == DeckId.left ? children : children.reversed.toList(),
      );
    }
    return Column(
      children: [
        SizedBox(height: 56, child: buttons),
        const SizedBox(height: 8),
        Expanded(child: area),
      ],
    );
  }

  Widget _bottom(double centerWidth) {
    Widget sampler(DeckId id) => SizedBox(
          width: centerWidth * 0.62,
          child: DjButton(
            lit: _modes[id] == DeckMode.sampler,
            color: DjColors.forDeck(id),
            onTap: () => _toggleMode(id, DeckMode.sampler),
            child: const Text('SAMPLER'),
          ),
        );
    return Row(
      children: [
        const DeckTransport(deckId: DeckId.left),
        const SizedBox(width: 8),
        sampler(DeckId.left),
        const SizedBox(width: 8),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: centerWidth * 2.4),
              child: const CrossfaderBar(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        sampler(DeckId.right),
        const SizedBox(width: 8),
        const DeckTransport(deckId: DeckId.right, mirrored: true),
      ],
    );
  }
}
