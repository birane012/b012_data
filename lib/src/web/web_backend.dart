import 'package:sqflite_common/sqlite_api.dart';

import '../executor.dart';

/// Browser backend: not available yet.
class WebBackend implements Backend {
  @override
  Future<OpenedDatabase> open(String nameOrPath) =>
      throw UnsupportedError('b012_data does not run in a browser yet.');

  @override
  Future<Database> openRaw(String path) =>
      throw UnsupportedError('openDB is not available in a browser.');

  @override
  Future<void> delete(String path) =>
      throw UnsupportedError('b012_data does not run in a browser yet.');

  @override
  Future<String?> readPointer() async => null;

  @override
  Future<void> writePointer(String name) =>
      throw UnsupportedError('b012_data does not run in a browser yet.');
}

/// The backend of this platform.
Backend createBackend() => WebBackend();
