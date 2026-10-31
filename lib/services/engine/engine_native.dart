import 'package:flutter/services.dart';
import 'local_song.dart';

/// False on Android: songs come from YouTube.
const bool isWebEngine = false;

/// The Android engine (android/.../engine, MainActivity.kt).
class Engine {
  static const _channel = MethodChannel('djmusi/engine');
  const Engine();

  Future<T?> invokeMethod<T>(String method, [Map<String, Object?>? args]) =>
      _channel.invokeMethod<T>(method, args);
  Future<Map<String, Object?>?> invokeMapMethod(String method,
          [Map<String, Object?>? args]) =>
      _channel.invokeMapMethod<String, Object?>(method, args);
  Future<List<Object?>?> invokeListMethod(String method,
          [Map<String, Object?>? args]) =>
      _channel.invokeListMethod<Object?>(method, args);
}

/// Only the web version opens songs from the device.
Future<List<LocalSong>> pickLocalSongs({bool multiple = false}) =>
    Future.error(UnsupportedError('Only in the web version'));

String localSongUrl(String id) => '';
