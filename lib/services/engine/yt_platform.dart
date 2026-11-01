/// Web version: plays YouTube videos in YouTube's own player.
library;

export 'yt_platform_stub.dart'
    if (dart.library.js_interop) 'yt_platform_web.dart';
