# DJ Musi app: where we left off (updated 2026-10-30, v14)

## Decisions
- Platform: the Flutter app from September (Dart), Android phones and tablets only for now. No Mac available, so no iOS yet.
- YouTube playback is a must (youtube_explode_dart, on the device itself).
- The web/TypeScript rebuild was considered and dropped, since Baz wants phones and tablets, not a PC.

## Done this session
- Added the Android project files (`flutter create --platforms=android`, org `com.baz.djmusi`) and the INTERNET permission.
- Crossfader now uses a real equal-power (cos/sin) curve. Before, it was a linear fade that dipped in the middle.
- Scratching: seeks are throttled to about one every 40 ms, so the player isn't flooded and the audio stutters less. The vinyl now follows your finger, and the position is clamped to the track length.
- Each deck shows a spinner while its track loads.
- Turntables size themselves to fit the screen (phone portrait or tablet landscape).
- `flutter analyze` reports no issues (Flutter 3.47.8). It has NOT been run on a device or built into an APK yet.

## Done 2026-10-27
- Tempo slider on each deck (+/-16%, double-tap to reset). It uses just_audio setSpeed, which keeps the pitch the same.
- CUE button: while paused it sets the cue point; while playing it jumps back to the cue point.
- Loop button: press once for LOOP IN, again for LOOP OUT (starts looping), again to EXIT LOOP. A position stream checked every 15-30 ms handles the jump back.
- Cue point and loop reset when a new track is loaded.
- Checked the layout with a throwaway web build at phone (390x844) and tablet (1180x820) sizes: no overflow.
- APK build is BLOCKED: the cloud environment's network policy refuses dl.google.com (fixed later the same day, see below).

## Done 2026-10-27 (evening)
- Built a release APK from dj_musi_app_v3.zip with Flutter 3.47.8 and Android SDK 36 (debug-signed, fine for sideloading): `DJ-Musi-tablet.apk` (57 MB, package com.baz.djmusi.dj_musi_app, v0.1.0). Install steps in INSTALL-ON-TABLET.md.
- Maven Central returned 429 rate limits once during the build; simply retrying worked.

## Done 2026-10-27 (evening): "no sound in DJ mode" fix (v4)
- Baz reported silence in DJ mode on the tablet (first APK build, from v3).
- Upgraded youtube_explode_dart 2.5.3 -> 3.1.0 and just_audio 0.9.46 -> 0.10.6.
- Audio stream now requested via the androidVr and androidSdkless clients, preferring MP4/AAC. Falls back to the muxed stream if audio-only fails.
- A track title now appears only after a successful load. Load errors show as a message at the bottom of the screen instead of failing silently.
- play() is no longer awaited (just_audio's future only completes when playback stops), and the UI refreshes from playerStateStream.
- SFX buttons show "No sound file yet" instead of failing silently.
- This could NOT be tested against YouTube from the cloud (youtube.com isn't reachable from the old environment).

## Done 2026-10-28: v5, still chasing "no sound in DJ mode"
- Baz's report: the Stream tab plays fine. In DJ mode the title shows and the wheel spins, but there's no sound. So setUrl succeeds on the audio-only URL, but playback stays silent (probably stuck buffering or blocked by YouTube).
- DJ decks now load the MUXED stream first (the same one the Stream tab uses, which is proven to work on the tablet), with audio-only as the fallback.
- Playback errors (from playbackEventStream) are shown on screen. The wheel spins only when audio is really playing, and shows a spinner while buffering.

## Done 2026-10-28: v6, playlists and search history (Baz's request)
- New Library tab (third tab): stat cards, a "Recently played" strip (tap to play, long-press to add to a playlist), and a grid of playlists (cover = first song's thumbnail). Tap a playlist to open it: play songs, "Load on left/right deck" (jumps to DJ Mode), drag to reorder, remove, rename, delete.
- A "+" (playlist_add) button on every search result, in both the Stream tab and the DJ deck search sheet.
- The last 10 searches show as chips under the search box (tap to re-run, x to remove, Clear).
- The DJ deck search sheet shows "From your playlists" before you search.
- Everything is stored with shared_preferences (lib/services/library_service.dart). There's a unit test in test/library_test.dart.
- Shared search UI lives in lib/widgets/track_search_panel.dart. Bottom nav tab switching goes through AppTabController in main.dart.

## Done 2026-10-28: v7, edjing Mix-style look (Baz likes edjing Mix's look and feel)
- DJ Mode was restyled: near-black background, deck A electric blue, deck B orange (lib/theme/dj_colors.dart).
- Platters: glowing ring (brighter while playing), black vinyl with grooves, the song's thumbnail as the center label, a colored marker line, a glossy reflection. They spin at about 33 RPM.
- Each deck has an info bar (letter badge, title/artist, elapsed/remaining time, a progress strip you can tap or drag to seek), a TEMPO slider, and round CUE / big PLAY / LOOP buttons (lib/widgets/deck_panel.dart).
- Landscape (tablet): deck | center VOLUME mixer with vertical faders | deck, with FX pads and a blue-to-orange crossfader along the bottom. Portrait: decks side by side, then horizontal volume faders, crossfader and FX pads. Double-tap the crossfader to center it.
- pubspec version is 0.7.0+7.

## Done 2026-10-28: v8, smoother scratching + device/Google Drive loading
- Baz confirmed the v6 decks DO play sound (muxed stream works). Baz's complaints: the records didn't turn smoothly under a finger, and they want scratching that feels smooth like edjing.
- Deck songs are now DOWNLOADED to the app cache (getTemporaryDirectory()/decks, keeping the last 15) via youtube_explode before playing, so seeking and scratching read local storage. Muxed stream first (proven), audio-only as fallback. If the download fails, it falls back to streaming the URL.
- The platter uses a raw Listener (instant grab, no drag slop) instead of GestureDetector pan. Touch pauses the sound, moving plays it (pauses after 90 ms of stillness), release resumes. Scratch mapping = one record turn per 1.8 s of audio (matches the 33 RPM spin). Microsecond accumulation.
- Verified in a web build with a test tone: a 5px touch move turns the record at once, and a half-turn drag moves the marker half a turn and the song about 0.9 s.
- Google Drive / device loading was built and then REMOVED at Baz's request ("not now"). To add it later: file_picker (FileType.audio) shows Drive in Android's picker; copy the picked file into the deck cache and call Deck.loadFile.
- Known limit: just_audio can't play backwards or at variable speed under a finger, so it won't match edjing. A real fix means swapping to a lower-level engine (e.g. flutter_soloud). Offered to Baz as a next step.
- pubspec version is 0.8.0+8.

## Done 2026-10-28: v9, karaoke + sound effects
- New Karaoke tab (3rd of 4: Stream, DJ Mode, Karaoke, Library). It searches YouTube with "karaoke" appended (history keeps the raw query) and plays full screen with the lyrics panel off by default.
- Synced lyrics in the video player (Stream/Library/Karaoke): LRCLIB /api/search?q=<cleaned title>, preferring synced lyrics within 10 s of the video length, then any synced, then plain. The current line is highlighted and centered; tap a line to jump. The lyrics button in the app bar toggles it. lib/services/lyrics_service.dart, lib/widgets/lyrics_view.dart. lrclib.net is blocked from the cloud environment, so the live API is untested; it's unit-tested with a mock (test/lyrics_test.dart).
- Sound effects: air_horn.mp3, siren.mp3 and scratch_hit.mp3 in assets/sounds, synthesized with ffmpeg in-house (no licensing issues). Copies are in /mnt/project-files/dj-app/sounds/.
- pubspec version is 0.9.0+9.

## Next steps
1. (Done) APK built.
2. Test on a real device: YouTube search and load, both decks, crossfader, how scratching feels.
3. Phase 2 (remaining): 3-band EQ (AndroidEqualizer, or switch the audio engine to flutter_soloud for better DJ effects), BPM detection/sync, waveform.
- Bumped pubspec version to 0.6.0+6 after the v6 build (the v6 APK itself still has versionCode 1). Bump it again for each future build.

## Paused 2026-10-28 (resumed same day, see below)
Baz likes v9 and will come back later. Open items: feedback on how scratching and lyrics feel on the real tablet. Ideas for later: more karaoke work (mic + echo, recording), Google Drive/device loading (built once in v8, then removed), EQ/BPM sync/waveforms, and a lower-level audio engine (flutter_soloud) for edjing-style scratching.

## 2026-10-28 (evening): v10 = "Build 1" of the edjing push (Baz: "finish the 2 builds")
Baz shared an edjing Mix tutorial video, which can't be watched from the cloud; the layout came from Bonedo's edjing Mix review instead. Baz wants the FREE edjing feature set. Plan:
- Build 1 (v10): new native audio engine for smooth, edjing-like scratching, plus scrolling waveforms. DONE, see below.
- Build 2 (v11): 3-band EQ per deck, hot cues, loop sizes (beats), FX (echo, filter, flanger), BPM + SYNC.

v10 details:
- Decks no longer use just_audio. There's a native engine in android/app/src/main/java/com/baz/djmusi/engine/:
  - AudioDecoder: MediaExtractor/MediaCodec decodes the whole song to 16-bit stereo in direct (off-heap) memory.
  - DeckEngine (pure Java): signed-rate playhead with linear interpolation. Scratching sets a target, and the playhead chases it (12 ms lag, max 12x, smoothed). Motor start/stop ramp is 60 ms, loops are sample-accurate, and waveform peaks are 100/s.
  - DjAudioEngine: low-latency float AudioTrack, 256-frame chunks, URGENT_AUDIO thread, tanh soft limiter.
  - MainActivity.kt: MethodChannel "djmusi/engine" (load, play, seek, tempo, gain, loop, scratchStart/Move/End, state).
- Tempo now changes pitch, like a real turntable. There's no key lock.
- Dart: lib/services/audio_service.dart talks to the engine and polls state every 33 ms. Deck.position extrapolates between polls. The record's angle comes from the song position (1 turn = 1.8 s).
- lib/widgets/waveform.dart: WaveformPanel (both decks stacked at the top, ±4 s, playhead in the center, drag to move).
- Engine unit test: tool/engine_test (javac/java). All checks pass: reverse scratch, landing accuracy, no jumps, silence when held, loop, tempo, end-of-song.
- just_audio is now only used for the SFX pads. A song must download first: there's no streaming fallback for decks.
- manifest: largeHeap=true, app label "DJ Musi". Version 0.10.0+10.
- v10 APK built by the build thread (engine test ALL PASS, flutter test 6/6). No emulator there (no /dev/kvm), so first run is on Baz's tablet.

## 2026-10-28 (evening): v11 = "Build 2" of the edjing push
- Engine (Java): Biquad.java (RBJ filters), BeatDetector.java (onset autocorrelation + fine grid search; detects 96/123.5/128/140/174 BPM exactly in tests). DeckEngine now applies EQ (low shelf 180 Hz, mid peak 1 kHz, high shelf 5 kHz; -26..+6 dB), a DJ filter (-1 low-pass .. +1 high-pass) and FX (echo, delay = half a beat; flanger).
- MainActivity.kt: new channel methods eq, filter, fx; load also returns bpm and firstBeatMs.
- Dart: Deck has bpm/liveBpm, hot cues (4), autoLoop(1/2/4/8/16 beats, beat-aligned), EQ/filter/FX state, and syncTo (tempo match with double/half-time handling, then phase-align).
- UI: lib/widgets/deck_tools.dart: per-deck EQ | CUES | LOOP | FX tab strip under the platter; tap the open tab to fold it away. The LOOP round button became SYNC (manual loop IN/OUT moved into the LOOP page). BPM shows in each deck's info bar.
- Engine tests: tool/engine_test/EngineTest.java and EngineTest2.java (see README there). Both ALL PASS.
- Layout checked in a web build (phone 390x844, tablet 1280x800) with panels open: no overflow.
- Web checks now need `flutter build web --no-web-resources-cdn` (gstatic is blocked in this environment). The web copy lives in /home/claude/webcheck.
- Version 0.11.0+11.
- v11 APK built (all tests pass). Baz: "it looks great. We are good for now."

## 2026-10-30: v12, music-app controls in the video player (Baz asked for karaoke mode)
- lib/screens/video_player_screen.dart rewritten. The player now takes a queue (the search results, playlist or recently played list the song was tapped from) and has: seek slider with elapsed/remaining time, play/pause (also tap the video), back/forward 10 s (also double-tap left/right of the video), previous (restarts if more than 3 s in) / next, shuffle, repeat off/all/one, auto-play of the next song, volume slider + mute (remembered between songs), add to playlist, and an "Up next" list.
- Applies to Stream, Karaoke and Library, since they share the player. Tablet landscape: lyrics sit to the right of the video.
- TrackSearchPanel.onTrackTap now also gets the results list. openTrackPlayer(context, track, queue:, showLyrics:).
- Not done: background playback and lock-screen/notification controls (would need audio_service + a different player).
- Version 0.12.0+12.
- v12 APK built (all tests pass).

## 2026-10-30: v13, edjing-style DJ screen (Baz sent an edjing screenshot + 2 videos)
- Baz: "make the DJ mode look like the picture and video" and "test the horn siren and scratch buttons, they seem not to have any sound file".
- SFX fix: the pads no longer use just_audio (removed from pubspec, sfx_service.dart deleted). They're now a Sampler inside the native engine (SamplerEngine.java, mixed by Mixer.java). Dart copies assets/sounds/*.mp3 to the temp folder on first tap and calls sampleLoad/sampleTrigger/sampleVolume. Errors now show their real message. Exact cause of the silence under just_audio wasn't confirmed (no device here); the bundled files were in the APK.
- 6 sampler pads: Air horn, Siren, Scratch + new Laser, Riser, Rewind (synthesized with ffmpeg, also in dj-app/sounds/).
- Engine: headphone cue = split mode (left ear mono mix, right ear cued decks pre-fader); waveform "tones" per peak (bass=red .. bright=cyan); flanger speed uses the fx delayMs param. Tests: tool/engine_test/EngineTest3.java.
- DJ Mode is now full screen, landscape-locked, no bottom nav; MENU pill (top center) leads to the other tabs (main.dart).
- Layout (home_screen.dart): top = BPM box + PITCH per side, deck title/time + whole-song overview waveform per deck, mirrored colored center waveform with beat lines. Middle = per deck FX / LOOP / SMART EQ / HOT CUES (row on tablets, column at the edge on short phone screens) + turntable or the mode panel; center strip = load buttons, channel faders, headphone buttons, AUTOMIX, SYNC. Bottom = PLAY, SET + jump-to-cue, SAMPLER, crossfader with slide arrows.
- Panels (deck_tools.dart): FX = two XY pads (echo/flanger with lock; filter), LOOP = size picker 1/8..32 + grid + IN/OUT, SMART EQ = vertical LOW/MID/HIGH/GAIN faders, HOT CUES = 4 colored pads, SAMPLER, PITCH.
- Turntable: tonearm (swings on when playing), +/- pitch bend (hold), deck-colored glow, "DJ MUSI / DECK A" label when empty. Our own branding and colors (blue A / orange B), no edjing logos.
- Automix: pick a playlist or recent songs; preloads the next song on the idle deck, starts it ~11 s before the end at its first beat, syncs, crossfades over 10 s.
- Center SYNC syncs the deck the crossfader favors less to the other.
- Web layout check uses ?fake=1 with a patched copy in /home/claude/webcheck (patch kept at scratchpad fake_audio_service.dart); not part of the app.
- Version 0.13.0+13.
- v13 APK built (engine tests 1-3 ALL PASS, flutter test 6/6).

## 2026-10-30: v14, Stream: search while playing, queue, autoplay (Baz's request)
- lib/services/player_service.dart: PlayerController (Provider in main.dart) owns the video player, the queue (playQueue, playNow, playNext, addToQueue, move, removeAt, jumpTo), shuffle/repeat (enum PlayRepeat; RepeatMode clashes with Flutter), volume/mute, and autoplay.
- Autoplay (on by default): when the last queued song starts, suggestFor() adds 5 songs, alternating YouTube related videos (YoutubeService.related, via youtube_explode getRelatedVideos) and a search for something from Baz's activity (recent artists, recent searches, playlist artists). Skips the last 30 played, and anything under 90 s or over 12 min. Suggestions are labeled "Suggested"; songs you add go before them.
- lib/widgets/mini_player.dart: bar above the bottom tabs (not in DJ mode) with play/pause, next, queue, stop; tap for the full player. The full player (video_player_screen.dart) now just shows the shared controller; the down arrow minimizes it. The queue sheet has the autoplay switch, drag to reorder, swipe to remove.
- Stream tab: tapping a result plays it now and stays on the search; + adds to queue; menu has Play now / Play next / Add to queue / Add to playlist. Karaoke and Library still open the full player with their list as the queue.
- Opening DJ mode pauses the music player.
- Tests: test/player_test.dart (fake YouTube): suggestion filtering/mix, queue ops, autoplay top-up. flutter test 9/9.
- Version 0.14.0+14.

## 2026-10-31: v15, browser version for testing (Baz: "Where is it?")
- The earlier "web build" was only a throwaway layout check and was never hosted. This is a real one.
- Live link (private to Baz until shared from the page's Share menu): https://claude.ai/artifact/LkvVmiC99FHfVbX3w5whbg . Hosted as a claude.ai Artifact; update it by republishing the same artifact URL.
- Built files: dj-app/dj-musi-web-v15.zip (contents of the published site; the page itself is dj-musi.html, which the Artifact host wraps in <html><body>). Source: dj_musi_app_v15.zip.
- Web audio engine: web/dj_engine_core.js is a straight port of DeckEngine/Biquad/SamplerEngine/Mixer to JS, run in an AudioWorklet (ScriptProcessor fallback). web/dj_engine.js decodes files (decodeAudioData -> 16-bit stereo), computes peaks/tones and BPM (port of BeatDetector), and exposes window.djEngine.call(method, json) with the same method names as the Android channel, plus pickFiles() and urlFor().
- Dart: lib/services/engine/engine_bridge.dart picks engine_native.dart (MethodChannel) or engine_web.dart (js_interop). isWebEngine switches the UI. Local songs are Tracks with videoId "local:<id>" (lib/services/engine/local_song.dart).
- Web UI: Stream tab -> "My music" (open songs from the device, play them in the music player, load on deck A/B). DJ LOAD opens "Load deck A/B" with an open button + already-opened songs. Automix can "Pick songs to mix". Karaoke shows a note (YouTube only on Android). Orientation lock is skipped on web (it blocked the file picker in Chrome).
- YouTube is NOT in the web version: browsers block youtube_explode_dart (CORS). Would need a proxy server; open question for Baz.
- Songs opened in the browser are forgotten on reload (browser rule), and are not added to Recently played/playlists.
- Tested in headless Chromium (phone 390x844, landscape 844x390): music player plays a picked MP3; deck A/B load, 120 BPM test track detected as 120.0, play, scratch moves the playhead back, sampler pads load. NOT tested on a real iPhone/Safari yet, and not confirmed inside the claude.ai artifact viewer (its security rules could block the WebAssembly renderer).
- Build: flutter build web --release --no-web-resources-cdn --no-wasm-dry-run; publish only canvaskit/canvaskit.{js,wasm} (bootstrap forces canvasKitVariant "full"); the artifact host refuses .bin and .frag files, which the web app doesn't need.
- Version 0.15.0+15. flutter analyze clean, flutter test 9/9.
