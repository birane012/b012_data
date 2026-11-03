import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' show databaseFactorySqflitePlugin;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../encryption.dart';
import '../executor.dart';
import 'locations.dart';

/// sqflite on Android, iOS and macOS (the plugin), `sqflite_common_ffi` on
/// Windows and Linux.
class NativeBackend implements Backend {
  NativeBackend() {
    if (_needsFfi) sqfliteFfiInit();
  }

  static bool get _needsFfi => Platform.isWindows || Platform.isLinux;

  DatabaseFactory get factory =>
      _needsFfi ? databaseFactoryFfi : databaseFactorySqflitePlugin;

  Future<DatabaseFactory>? _encrypting;

  /// `sqflite_common_ffi` over the SQLite bundled by `package:sqlite3`,
  /// once checked to be SQLite3MultipleCiphers. On Android and iOS too: an
  /// encrypted database never goes through the system SQLite.
  Future<DatabaseFactory> _encryptingFactory() => _encrypting ??=
      () async {
        sqfliteFfiInit();
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

  /// The absolute path of the application database [name].
  Future<String> _absolutePath(String name) async {
    final String resolved = await Locations.instance.resolveDatabase(name);
    if (p.isAbsolute(resolved)) return resolved;
    return p.join(
      await databaseFactorySqflitePlugin.getDatabasesPath(),
      resolved,
    );
  }

  /// Whether [path] holds something that is not plain SQLite (an encrypted
  /// database, typically). Opening it without its key through the system
  /// SQLite of Android would erase it, as a corrupt file.
  static Future<bool> _isProtected(String path) async {
    final File file = File(path);
    if (!await file.exists() || await file.length() < sqliteHeader.length) {
      return false;
    }
    final RandomAccessFile raf = await file.open();
    try {
      return !isPlainSqlite(await raf.read(sqliteHeader.length));
    } finally {
      await raf.close();
    }
  }

  static Future<bool> _isPlain(String path) async {
    final File file = File(path);
    if (!await file.exists() || await file.length() < sqliteHeader.length) {
      return false;
    }
    final RandomAccessFile raf = await file.open();
    try {
      return isPlainSqlite(await raf.read(sqliteHeader.length));
    } finally {
      await raf.close();
    }
  }

  Future<OpenedDatabase> _openEncrypted(String name, String key) async {
    final DatabaseFactory ffi = await _encryptingFactory();
    final String path = await _absolutePath(name);
    if (await _isPlain(path)) {
      throw StateError(
        'The database $path is not encrypted: call '
        'DataAccess.instance.encryptDatabase(key) to encrypt it in place.',
      );
    }
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
      executor: NativeExecutor(db),
      database: db,
      path: db.path,
      close: db.close,
    );
  }

  @override
  Future<void> encryptInPlace(String name, String key) async {
    final String path = await _absolutePath(name);
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

  @override
  Future<OpenedDatabase> open(String nameOrPath, OpenOptions options) async {
    final String? key = options.key;
    if (key != null) return _openEncrypted(nameOrPath, key);
    final String absolute = await _absolutePath(nameOrPath);
    if (await _isProtected(absolute)) throw StateError(keyNeeded(absolute));
    final String path = await Locations.instance.resolveDatabase(nameOrPath);
    final Database db = await factory.openDatabase(path);
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

  @override
  Future<String?> readPointer() => Locations.instance.readPointer();

  @override
  Future<void> writePointer(String name) =>
      Locations.instance.writePointer(name);
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
