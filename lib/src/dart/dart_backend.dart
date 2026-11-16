import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../encryption.dart';
import '../executor.dart';
import 'dart_locations.dart';

/// Engine of the Flutter-free entry (`package:b012_data/b012_data_dart.dart`):
/// `sqflite_common_ffi` over the SQLite bundled by `package:sqlite3`, the
/// databases in [databasesDirectory]. Same encryption rules as the native
/// engine (it mirrors `native/native_backend.dart`, which keeps its own copy
/// so that the Flutter path does not change): the engine must be
/// SQLite3MultipleCiphers, a plain database is never opened with a key, a
/// wrong key is refused.
class DartBackend implements Backend {
  DartBackend() {
    sqfliteFfiInit();
  }

  DatabaseFactory get factory => databaseFactoryFfi;

  Future<DatabaseFactory>? _encrypting;

  Future<DatabaseFactory> _encryptingFactory() => _encrypting ??= () async {
        final Database probe = await databaseFactoryFfi.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(singleInstance: false),
        );
        try {
          requireEncryptingEngine(await probe.rawQuery('PRAGMA cipher'));
        } finally {
          await probe.close();
        }
        return databaseFactoryFfi;
      }().catchError((Object e) {
        _encrypting = null;
        throw e;
      });

  /// [name] if absolute, else inside [databasesDirectory].
  String _absolutePath(String name) =>
      p.isAbsolute(name) ? name : p.join(databasesDirectory(), name);

  static Future<List<int>?> _header(String path) async {
    final File file = File(path);
    if (!await file.exists() || await file.length() < sqliteHeader.length) {
      return null;
    }
    final RandomAccessFile raf = await file.open();
    try {
      return await raf.read(sqliteHeader.length);
    } finally {
      await raf.close();
    }
  }

  static Future<bool> _isPlain(String path) async {
    final List<int>? h = await _header(path);
    return h != null && isPlainSqlite(h);
  }

  static Future<bool> _isProtected(String path) async {
    final List<int>? h = await _header(path);
    return h != null && !isPlainSqlite(h);
  }

  Future<OpenedDatabase> _openEncrypted(String path, String key) async {
    final DatabaseFactory ffi = await _encryptingFactory();
    if (await _isPlain(path)) {
      throw StateError(
        'The database $path is not encrypted: call '
        'DataAccess.instance.encryptDatabase(key) to encrypt it in place.',
      );
    }
    await Directory(p.dirname(path)).create(recursive: true);
    final Database db = await ffi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        onConfigure: (Database d) =>
            d.execute('PRAGMA key = ${sqlLiteral(key)}'),
      ),
    );
    try {
      await db.rawQuery('SELECT count(*) FROM sqlite_master');
    } catch (_) {
      await db.close();
      throw StateError(
        'The encryption key does not open $path (wrong key, or not a database).',
      );
    }
    return OpenedDatabase(
      executor: DartExecutor(db),
      database: db,
      path: db.path,
      close: db.close,
    );
  }

  @override
  Future<OpenedDatabase> open(String nameOrPath, OpenOptions options) async {
    final String path = _absolutePath(nameOrPath);
    final String? key = options.key;
    if (key != null) return _openEncrypted(path, key);
    if (await _isProtected(path)) throw StateError(keyNeeded(path));
    await Directory(p.dirname(path)).create(recursive: true);
    final Database db = await factory.openDatabase(path);
    return OpenedDatabase(
      executor: DartExecutor(db),
      database: db,
      path: db.path,
      close: db.close,
    );
  }

  @override
  Future<Database> openRaw(String path) =>
      factory.openDatabase(_absolutePath(path));

  @override
  Future<void> delete(String path, OpenOptions options) =>
      factory.deleteDatabase(_absolutePath(path));

  @override
  Future<void> encryptInPlace(
    String name,
    String key,
    OpenOptions options,
  ) async {
    final String path = _absolutePath(name);
    if (!await _isPlain(path)) return;
    final DatabaseFactory ffi = await _encryptingFactory();
    final Database db = await ffi.openDatabase(
      path,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    try {
      await db.rawQuery('PRAGMA rekey = ${sqlLiteral(key)}');
    } finally {
      await db.close();
    }
    if (await _isPlain(path)) {
      throw StateError('The database $path could not be encrypted.');
    }
  }

  File get _pointer => File(p.join(databasesDirectory(), 'dbName'));

  @override
  Future<String?> readPointer() async =>
      await _pointer.exists() ? _pointer.readAsString() : null;

  @override
  Future<void> writePointer(String name) async {
    await _pointer.parent.create(recursive: true);
    await _pointer.writeAsBytes(utf8.encode(name), flush: true);
  }
}

/// [SqlExecutor] over a `sqflite_common` database or transaction.
class DartExecutor implements SqlExecutor {
  DartExecutor(this._executor);

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
        (Transaction txn) => action(DartExecutor(txn)),
      );
    }
    return action(this);
  }
}

Backend createBackend() => DartBackend();
