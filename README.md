# DJ Musi

Personal music player + two-turntable DJ mixer (Flutter).

**Try it in a browser:** https://bazinmelesse.github.io/Jd-app/ (plays songs saved on your device; YouTube search is Android-only for now).

- Android app: `flutter build apk`
- Web version: `flutter build web --release --no-web-resources-cdn`, then copy `build/web` to `docs/` (GitHub Pages serves `docs/`). The web DJ engine is in `web/dj_engine.js` and `web/dj_engine_core.js`.
- Progress notes: `STATUS.md`

---

# DJ Musi — Personal Music + DJ Mixer App (Phase 1)

A personal, non-commercial Flutter app: search & stream audio pulled from
YouTube, load two tracks onto side-by-side turntables, and mix them with a
crossfader, per-deck volume, drag-to-scratch, and a few DJ drop sound effects.

## What's included in this phase

The app has two modes, switched via the bottom navigation bar:

**Stream tab** (Musi-style watch/listen)
- Search YouTube and browse results with thumbnails
- Tap a result to watch/listen to it full-screen (actual video playback, not just audio)

**DJ Mode tab**
- YouTube search + audio-stream extraction (`youtube_explode_dart`)
- Two independent playback decks (`just_audio`)
- Side-by-side turntable UI with spin animation
- Drag-to-scratch gesture (spin the vinyl with your finger to nudge playback)
- Crossfader with equal-power curve + per-deck volume sliders
- Bundled sound-effect buttons (air horn / siren / scratch hit)

**Not yet built** (future phases): EQ bands, tempo/BPM matching, waveform
display, saved playlists, looping.

## 1. Install Flutter on Windows

1. Download the Flutter SDK zip: https://docs.flutter.dev/get-started/install/windows
2. Extract it somewhere permanent, e.g. `C:\src\flutter`
3. Add `C:\src\flutter\bin` to your PATH (System Properties → Environment Variables)
4. Open a new terminal and run:
   ```
   flutter doctor
   ```
   This tells you what's missing (Android SDK, Chrome, etc.) and gives
   step-by-step fixes. Follow it until things are green.
5. Install **Android Studio** (Flutter uses its Android SDK/tooling even if
   you never open the IDE itself) and, in it, install the Android SDK and an
   emulator via Settings → SDK Manager.

## 2. Get the project running

1. Unzip this project folder anywhere, e.g. `C:\projects\dj_musi_app`
2. Open a terminal in that folder and run:
   ```
   flutter pub get
   ```
   This downloads all the packages listed in `pubspec.yaml`.
3. Add sound effect files (see below), then plug in a phone or start an
   emulator, and run:
   ```
   flutter run
   ```

## 3. Sound effects (you need to add these yourself)

I didn't bundle actual audio files — you'll want royalty-free clips. Grab
free ones from a site like **freesound.org** or **pixabay.com/sound-effects**
and drop them into `assets/sounds/` with these exact filenames:

- `air_horn.mp3`
- `siren.mp3`
- `scratch_hit.mp3`

(You can add more buttons in `lib/screens/home_screen.dart` — just copy one
of the existing `ElevatedButton.icon(...)` blocks and point it at a new file.)

## 4. About iOS specifically

This is a cross-platform Flutter project, so `flutter run` targets whatever
device is connected — Android phone/emulator is the easy path from Windows.
Building and installing an **actual iOS build still requires a Mac** at some
point (Apple's tooling, Xcode, code signing — there's no way around this).
Options when you're ready for that step:
- Borrow/rent Mac time briefly just to run `flutter build ios` and sideload
  once, or
- Use a cloud Mac service (e.g. MacStadium, GitHub Actions macOS runners) to
  build the iOS binary from this same codebase without owning a Mac.

Everything else — writing, testing, and using the app day-to-day on Android —
works fine on Windows alone.

## Legal note (read this)

Pulling playable audio streams directly from YouTube outside their official
Data API / licensing terms sits in a legal gray area — it's the same
approach apps like Musi use, and it's why Musi has drawn scrutiny from the
music industry. Because this project is personal and non-commercial, the
practical risk is low, but:
- Don't publish this to the App Store / Play Store
- Don't monetize it or distribute it to others
- Treat it as a private, personal-use tool only

## Project structure

```
dj_musi_app/
├── pubspec.yaml
├── lib/
│   ├── main.dart                     # App entry point
│   ├── models/track.dart             # Track data model
│   ├── services/
│   │   ├── youtube_service.dart      # YouTube search + stream URL extraction
│   │   ├── audio_service.dart        # Dual-deck playback + crossfader logic
│   │   └── sfx_service.dart          # DJ drop sound effects
│   ├── widgets/
│   │   ├── turntable_widget.dart     # Spinning vinyl + scratch gesture
│   │   └── track_search_sheet.dart   # YouTube search bottom sheet
│   └── screens/home_screen.dart      # Main layout: decks + crossfader + SFX
└── assets/sounds/                    # (you add .mp3 files here)
```

## Next steps once this is running

Tell me how the first run goes and we'll tackle Phase 2 — EQ bands, BPM
detection/tempo matching, and a waveform view. We can also swap the scratch
gesture math if it doesn't feel right on a real touchscreen (drag speed vs.
angle sensitivity is very much a "feel" thing you tune by testing).
