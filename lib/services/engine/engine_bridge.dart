/// Talks to the DJ audio engine: the native one on Android (a
/// MethodChannel), or the Web Audio one (web/dj_engine.js) in a browser.
library;

export 'engine_native.dart' if (dart.library.js_interop) 'engine_web.dart';
