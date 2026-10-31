import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'local_song.dart';

/// True in a browser: decks play songs opened from the device.
const bool isWebEngine = true;

@JS('djEngine.call')
external JSPromise<JSString> _call(String method, String argsJson);

@JS('djEngine.pickFiles')
external JSPromise<JSString> _pickFiles(bool multiple);

@JS('djEngine.urlFor')
external String _urlFor(String id);

/// The Web Audio engine in web/dj_engine.js, with the same methods as the
/// Android one.
class Engine {
  const Engine();

  Future<Object?> _invoke(String method, Map<String, Object?>? args) async {
    try {
      final out = await _call(method, jsonEncode(args ?? const {})).toDart;
      return _fix(jsonDecode(out.toDart));
    } catch (e) {
      throw Exception(_message(e));
    }
  }

  static String _message(Object e) {
    final s = e.toString();
    return s.startsWith('Exception: ') ? s.substring(11) : s;
  }

  /// Waveform lists come back as JSON numbers; the app wants Float32List.
  static Object? _fix(Object? v) {
    if (v is Map) {
      return {
        for (final e in v.entries)
          e.key as String: (e.key == 'peaks' || e.key == 'tones')
              ? Float32List.fromList(
                  (e.value as List).map((x) => (x as num).toDouble()).toList())
              : e.value
      };
    }
    return v;
  }

  Future<T?> invokeMethod<T>(String method, [Map<String, Object?>? args]) async =>
      await _invoke(method, args) as T?;
  Future<Map<String, Object?>?> invokeMapMethod(String method,
          [Map<String, Object?>? args]) async =>
      (await _invoke(method, args) as Map?)?.cast<String, Object?>();
  Future<List<Object?>?> invokeListMethod(String method,
          [Map<String, Object?>? args]) async =>
      (await _invoke(method, args) as List?)?.cast<Object?>();
}

/// Opens the phone's file picker. Call it straight from a tap (before any
/// await), or the browser blocks it.
Future<List<LocalSong>> pickLocalSongs({bool multiple = false}) async {
  final out = await _pickFiles(multiple).toDart;
  return [
    for (final f in jsonDecode(out.toDart) as List)
      LocalSong(f['id'] as String, f['name'] as String)
  ];
}

/// A blob: URL the music player can play.
String localSongUrl(String id) => _urlFor(id);
