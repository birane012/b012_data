// Puts the WebAssembly SQLite modules b012_data needs in a browser into the
// web/ folder of the application:
//
//   dart run b012_data:setup_web [--web-dir web] [--force]
//
// The modules come from the GitHub release of package:sqlite3 matching the
// version resolved in the application's pubspec.lock, and are checked
// against the SHA-256 digests published with that release.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import 'package:crypto/crypto.dart';

const List<String> _modules = <String>['sqlite3mc.wasm', 'sqlite3.wasm'];

Future<void> main(List<String> args) async {
  String webDir = 'web';
  bool force = false;
  for (int i = 0; i < args.length; i++) {
    if (args[i] == '--force') {
      force = true;
    } else if (args[i] == '--web-dir' && i + 1 < args.length) {
      webDir = args[++i];
    } else {
      stderr.writeln(
        'Usage: dart run b012_data:setup_web [--web-dir web] [--force]',
      );
      exit(64);
    }
  }

  final File lock = File('pubspec.lock');
  if (!lock.existsSync()) {
    stderr.writeln(
      'pubspec.lock not found: run this from the application folder, '
      'after flutter pub get.',
    );
    exit(66);
  }
  final RegExpMatch? match = RegExp(
    r'^  sqlite3:\s*\n(?:    .*\n)*?    version: "([^"]+)"',
    multiLine: true,
  ).firstMatch(lock.readAsStringSync());
  if (match == null) {
    stderr.writeln('package:sqlite3 is not in pubspec.lock.');
    exit(65);
  }
  final String version = match.group(1)!;
  final String tag = 'sqlite3-$version';

  final HttpClient http = HttpClient()..userAgent = 'b012_data setup_web';
  try {
    final Map<String, String> digests = await _digests(http, tag);
    Directory(webDir).createSync(recursive: true);
    for (final String module in _modules) {
      final File target = File('$webDir${Platform.pathSeparator}$module');
      final String? expected = digests[module];
      if (expected == null) {
        stderr.writeln('$module is not published with $tag.');
        exit(69);
      }
      if (!force &&
          target.existsSync() &&
          sha256.convert(target.readAsBytesSync()).toString() == expected) {
        stdout.writeln('$module $version already in $webDir (checked).');
        continue;
      }
      final List<int> bytes = await _download(
        http,
        Uri.parse(
          'https://github.com/simolus3/sqlite3.dart/releases/download/$tag/$module',
        ),
      );
      final String actual = sha256.convert(bytes).toString();
      if (actual != expected) {
        stderr.writeln(
          '$module: SHA-256 $actual, expected $expected. Nothing written.',
        );
        exit(70);
      }
      target.writeAsBytesSync(bytes, flush: true);
      stdout.writeln('$module $version written to $webDir (SHA-256 checked).');
    }
  } finally {
    http.close();
  }
}

Future<Map<String, String>> _digests(HttpClient http, String tag) async {
  final List<int> body = await _download(
    http,
    Uri.parse(
      'https://api.github.com/repos/simolus3/sqlite3.dart/releases/tags/$tag',
    ),
  );
  final Object? release = jsonDecode(utf8.decode(body));
  final Map<String, String> digests = <String, String>{};
  if (release is Map && release['assets'] is List) {
    for (final Object? asset in release['assets'] as List<Object?>) {
      if (asset is Map &&
          asset['name'] is String &&
          asset['digest'] is String) {
        final String digest = asset['digest'] as String;
        digests[asset['name'] as String] = digest.startsWith('sha256:')
            ? digest.substring(7)
            : digest;
      }
    }
  }
  return digests;
}

Future<List<int>> _download(HttpClient http, Uri uri) async {
  final HttpClientRequest request = await http.getUrl(uri);
  final HttpClientResponse response = await request.close();
  if (response.statusCode != HttpStatus.ok) {
    throw HttpException('HTTP ${response.statusCode}', uri: uri);
  }
  final BytesBuilder bytes = BytesBuilder(copy: false);
  await response.forEach(bytes.add);
  return bytes.takeBytes();
}
