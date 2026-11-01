import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/audio_service.dart';
import 'services/library_service.dart';
import 'services/player_service.dart';
import 'widgets/mini_player.dart';
import 'theme/dj_colors.dart';
import 'screens/home_screen.dart';
import 'screens/karaoke_screen.dart';
import 'screens/library_screen.dart';
import 'screens/stream_screen.dart';
import 'screens/device_music_screen.dart';
import 'services/engine/engine_bridge.dart';
import 'services/engine/yt_platform.dart';
import 'services/youtube_web_search.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final library = LibraryController();
  await library.load();
  final youtubeKey = YoutubeKey();
  if (isWebEngine) {
    await youtubeKey.load();
    registerYoutubePlayer();
  }
  runApp(DjMusiApp(library: library, youtubeKey: youtubeKey));
}

/// The bottom-nav tabs, in order.
enum AppTab { stream, dj, karaoke, library }

/// Which tab is showing; lets other screens switch tabs (e.g. "Load on
/// left deck" from a playlist jumps to DJ Mode).
class AppTabController extends ValueNotifier<int> {
  AppTabController() : super(AppTab.stream.index);
}

class DjMusiApp extends StatelessWidget {
  final LibraryController library;
  final YoutubeKey youtubeKey;

  const DjMusiApp({super.key, required this.library, required this.youtubeKey});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MixerController()),
        ChangeNotifierProvider.value(value: library),
        ChangeNotifierProvider(
          create: (context) => PlayerController(
              youtube: context.read<MixerController>().youtube,
              library: library),
        ),
        ChangeNotifierProvider(create: (_) => AppTabController()),
        ChangeNotifierProvider(create: (_) => DeviceSongs()),
        ChangeNotifierProvider.value(value: youtubeKey),
      ],
      child: MaterialApp(
        title: 'DJ Musi',
        theme: ThemeData(
          brightness: Brightness.dark,
          colorSchemeSeed: DjColors.deckA,
          scaffoldBackgroundColor: DjColors.background,
          appBarTheme: const AppBarTheme(backgroundColor: DjColors.background),
          navigationBarTheme:
              const NavigationBarThemeData(backgroundColor: DjColors.panel),
          useMaterial3: true,
        ),
        home: const MainNavigation(),
      ),
    );
  }
}

/// Root screen: a bottom nav bar that switches between the Stream (Musi-style
/// watch/listen) tab, the DJ Mode (dual-turntable mixer) tab and the Library
/// (playlists dashboard) tab, plus Karaoke.
///
/// DJ Mode is full screen and sideways, like a real DJ app: the nav bar and
/// status bar hide, and its MENU button leads back to the other tabs.
class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  bool? _djShown;

  void _applyScreenMode(bool dj) {
    if (_djShown == dj) return;
    _djShown = dj;
    // The music player and the decks shouldn't play over each other.
    if (dj) context.read<PlayerController>().pause();
    // Browsers can't lock the screen sideways (and trying it blocks the
    // file picker), so the web version just asks you to turn the phone.
    if (isWebEngine) return;
    SystemChrome.setPreferredOrientations(dj
        ? const [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight
          ]
        : const []);
    SystemChrome.setEnabledSystemUIMode(
        dj ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
  }

  static const _screens = [
    StreamScreen(),
    HomeScreen(),
    KaraokeScreen(),
    LibraryScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final tab = context.watch<AppTabController>();
    final dj = tab.value == AppTab.dj.index;
    _applyScreenMode(dj);
    return Scaffold(
      body: IndexedStack(
        index: tab.value,
        children: _screens,
      ),
      bottomNavigationBar: dj
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const MiniPlayer(),
                NavigationBar(
                  selectedIndex: tab.value,
                  onDestinationSelected: (index) => tab.value = index,
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.play_circle_outline),
                      selectedIcon: Icon(Icons.play_circle),
                      label: 'Stream',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.album_outlined),
                      selectedIcon: Icon(Icons.album),
                      label: 'DJ Mode',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.mic_none),
                      selectedIcon: Icon(Icons.mic),
                      label: 'Karaoke',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.library_music_outlined),
                      selectedIcon: Icon(Icons.library_music),
                      label: 'Library',
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
