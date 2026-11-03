import 'dart:io';

import 'package:sqflite/sqflite.dart' show databaseFactorySqflitePlugin;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../executor.dart';

/// sqflite on Android, iOS and macOS (the plugin), `sqflite_common_ffi` on
/// Windows and Linux.
class NativeBackend implements Backend {
  NativeBackend() {
    if (_needsFfi) sqfliteFfiInit();
  }

  static bool get _needsFfi => Platform.isWindows || Platform.isLinux;

  DatabaseFactory get factory =>
      _needsFfi ? databaseFactoryFfi : databaseFactorySqflitePlugin;

  @override
  Future<OpenedDatabase> open(String nameOrPath) async {
    final Database db = await factory.openDatabase(nameOrPath);
    return OpenedDatabase(
      executor: NativeExecutor(db),
      database: db,
      path: db.path,
      close: db.close,
    );
  }

  @override
  Future<Database> openRaw(String path) => factory.openDatabase(path);

  @override
  Future<void> delete(String path) => factory.deleteDatabase(path);
}

/// [SqlExecutor] over a sqflite [Database] or [Transaction].
class NativeExecutor implements SqlExecutor {
  NativeExecutor(this._executor);

  final DatabaseExecutor _executor;

  @override
  Future<List<Map<String, Object?>>> select(
    String sql, [
    List<Object?> args = const <Object?>[],
  ]) => _executor.rawQuery(sql, args);

  @override
  Future<int> insert(String sql, [List<Object?> args = const <Object?>[]]) =>
      _executor.rawInsert(sql, args);

  @override
  Future<int> change(String sql, [List<Object?> args = const <Object?>[]]) =>
      _executor.rawUpdate(sql, args);

  @override
  Future<void> execute(String sql, [List<Object?> args = const <Object?>[]]) =>
      _executor.execute(sql, args);

  @override
  Future<T> transaction<T>(Future<T> Function(SqlExecutor tx) action) {
    final DatabaseExecutor executor = _executor;
    if (executor is Database) {
      return executor.transaction(
        (Transaction txn) => action(NativeExecutor(txn)),
      );
    }
    return action(this);
  }
}

/// The backend of this platform.
Backend createBackend() => NativeBackend();
