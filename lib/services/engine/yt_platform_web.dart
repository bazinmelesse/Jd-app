import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;
import 'package:flutter/widgets.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:web/web.dart' as web;

@JS('ytBridge.create')
external void _create(int id, String videoId, JSFunction onEvent);
@JS('ytBridge.dispose')
external void _dispose(int id);
@JS('ytBridge.play')
external void _play(int id);
@JS('ytBridge.pause')
external void _pause(int id);
@JS('ytBridge.seek')
external void _seek(int id, int ms);
@JS('ytBridge.setVolume')
external void _setVolume(int id, double v);
@JS('ytBridge.setSpeed')
external void _setSpeed(int id, double s);
@JS('ytBridge.positionMs')
external int _positionMs(int id);
@JS('ytBridge.attach')
external void _attach(int id, web.HTMLElement placeholder);

const _viewType = 'djmusi-youtube';

/// Makes video_player play "ytembed:<videoId>" sources in YouTube's own
/// embedded player (web/yt_player.js). Everything else (songs from the
/// device) still goes to the normal web video player.
void registerYoutubePlayer() {
  ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId,
      {Object? params}) {
    final div = web.HTMLDivElement()
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.background = '#000';
    _attach(params as int, div);
    return div;
  });
  VideoPlayerPlatform.instance =
      _YoutubeAwarePlatform(VideoPlayerPlatform.instance);
}

class _YoutubeAwarePlatform extends VideoPlayerPlatform {
  final VideoPlayerPlatform inner;
  _YoutubeAwarePlatform(this.inner);

  static int _nextId = 1 << 20; // well clear of the normal player's ids
  final Map<int, StreamController<VideoEvent>> _events = {};

  bool _isYt(int id) => _events.containsKey(id);

  @override
  Future<void> init() => inner.init();

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final uri = options.dataSource.uri ?? '';
    if (!uri.startsWith('ytembed:')) return inner.createWithOptions(options);
    final parsed = Uri.parse(uri);
    final videoId = parsed.path;
    final hintMs = int.tryParse(parsed.queryParameters['d'] ?? '') ?? 0;
    final id = _nextId++;
    final events = StreamController<VideoEvent>.broadcast();
    _events[id] = events;
    var initialized = false;
    var buffering = false;
    void onEvent(String json) {
      final e = jsonDecode(json) as Map<String, dynamic>;
      switch (e['type']) {
        case 'ready':
          if (initialized) return;
          initialized = true;
          var ms = (e['durationMs'] as num).toInt();
          if (ms <= 0) ms = hintMs;
          events.add(VideoEvent(
              eventType: VideoEventType.initialized,
              duration: Duration(milliseconds: ms),
              size: const Size(1280, 720)));
        case 'state':
          final s = e['state'] as int;
          if (s == 3 && !buffering) {
            buffering = true;
            events.add(VideoEvent(eventType: VideoEventType.bufferingStart));
          } else if (s != 3 && buffering) {
            buffering = false;
            events.add(VideoEvent(eventType: VideoEventType.bufferingEnd));
          }
          if (s == 1 || s == 2) {
            events.add(VideoEvent(
                eventType: VideoEventType.isPlayingStateUpdate,
                isPlaying: s == 1));
          } else if (s == 0) {
            events.add(VideoEvent(eventType: VideoEventType.completed));
          }
        case 'error':
          events.addError(Exception(e['message']));
      }
    }

    _create(id, videoId, onEvent.toJS);
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _isYt(playerId)
      ? _events[playerId]!.stream
      : inner.videoEventsFor(playerId);

  @override
  Future<void> dispose(int playerId) async {
    if (!_isYt(playerId)) return inner.dispose(playerId);
    _dispose(playerId);
    await _events.remove(playerId)?.close();
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {
    if (!_isYt(playerId)) return inner.setLooping(playerId, looping);
  }

  @override
  Future<void> play(int playerId) async =>
      _isYt(playerId) ? _play(playerId) : inner.play(playerId);

  @override
  Future<void> pause(int playerId) async =>
      _isYt(playerId) ? _pause(playerId) : inner.pause(playerId);

  @override
  Future<void> setVolume(int playerId, double volume) async => _isYt(playerId)
      ? _setVolume(playerId, volume)
      : inner.setVolume(playerId, volume);

  @override
  Future<void> seekTo(int playerId, Duration position) async => _isYt(playerId)
      ? _seek(playerId, position.inMilliseconds)
      : inner.seekTo(playerId, position);

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async =>
      _isYt(playerId)
          ? _setSpeed(playerId, speed)
          : inner.setPlaybackSpeed(playerId, speed);

  @override
  Future<Duration> getPosition(int playerId) async {
    if (!_isYt(playerId)) return inner.getPosition(playerId);
    return Duration(milliseconds: _positionMs(playerId));
  }

  @override
  Widget buildViewWithOptions(VideoViewOptions options) => _isYt(
          options.playerId)
      ? HtmlElementView(viewType: _viewType, creationParams: options.playerId)
      : inner.buildViewWithOptions(options);

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) =>
      inner.setMixWithOthers(mixWithOthers);

  @override
  Future<void> setAllowBackgroundPlayback(bool allow) =>
      inner.setAllowBackgroundPlayback(allow);

  @override
  Future<void> setWebOptions(
      int playerId, VideoPlayerWebOptions options) async {
    if (!_isYt(playerId)) return inner.setWebOptions(playerId, options);
  }
}
