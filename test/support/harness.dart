import 'dart:io';

import 'package:b012_data/b012_sqlflite_easy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// `path_provider` answering from a temporary directory.
class FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  FakePathProvider(this.root);

  final String root;

  String _join(String name) => '$root${Platform.pathSeparator}$name';

  @override
  Future<String?> getApplicationDocumentsPath() async => _join('Documents');

  @override
  Future<String?> getApplicationSupportPath() async => _join('Support');

  @override
  Future<String?> getTemporaryPath() async => _join('Temp');
}

/// A temporary directory that is both the fake home of `path_provider` and
/// the current directory, as an installed desktop application would see it.
class Sandbox {
  Sandbox._(this.dir, this._previousCwd);

  final Directory dir;
  final Directory _previousCwd;

  String path(String relative) =>
      '${dir.path}${Platform.pathSeparator}$relative';

  static Future<Sandbox> create() async {
    final Directory dir = await Directory.systemTemp.createTemp('b012_test_');
    Directory(
      '${dir.path}${Platform.pathSeparator}Documents',
    ).createSync(recursive: true);
    PathProviderPlatform.instance = FakePathProvider(dir.path);
    final Directory previous = Directory.current;
    Directory.current = dir;
    return Sandbox._(dir, previous);
  }

  Future<void> dispose() async {
    await DataAccess.instance.closeDB();
    Directory.current = _previousCwd;
    for (int attempt = 0; attempt < 5; attempt++) {
      try {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
  }
}

/// Closes the application database and deletes its file, so that each test
/// starts from an empty database.
Future<void> resetDatabase() async {
  final String path = (await DataAccess.instance.db).path;
  await DataAccess.instance.closeDB();
  await DataAccess.instance.dropDB(path);
}

/// Runs [body] in a fresh sandbox shared by the tests of a file.
void useSandbox() {
  late Sandbox sandbox;
  setUpAll(() async => sandbox = await Sandbox.create());
  tearDownAll(() async => sandbox.dispose());
  setUp(resetDatabase);
}
