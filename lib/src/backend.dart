// Flutter-free Dart (servers, command-line tools): `dart/dart_backend.dart` ;
// browser: `web/web_backend.dart` ; Flutter on a device or desktop:
// `native/native_backend.dart`. The first matching condition wins.
export 'dart/dart_backend.dart'
    if (dart.library.js_interop) 'web/web_backend.dart'
    if (dart.library.ui) 'native/native_backend.dart';
