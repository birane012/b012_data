import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:sqflite_common/sqlite_api.dart' show Database;
import 'package:sqlite3/wasm.dart';
import 'package:web/web.dart' as web;

import '../encryption.dart';
import '../executor.dart';

/// Browser backend over `package:sqlite3` (plan 1 of the 2.1 work showed
/// that `sqflite_common_ffi_web` can neither encrypt nor wait for a write to
/// be stored).
///
/// * SQLite runs as WebAssembly (`sqlite3mc.wasm` by default, which also
///   opens unencrypted databases), loaded from the application's `web/`
///   folder.
/// * Databases live in IndexedDB (`IndexedDbFileSystem`, database
///   `b012_data`); every write is flushed to IndexedDB before it returns.
/// * One tab at a time: a Web Lock is held while the database is open; a
///   second tab gets a clear error instead of a diverging copy.
class WebBackend implements Backend {
  static const String _idbName = 'b012_data';
  static const String _vfsName = 'b012_idb';
  static const String _pointerKey = 'b012_data.dbName';

  final Map<String, Future<_Engine>> _engines = <String, Future<_Engine>>{};
  bool _persistAsked = false;

  Future<_Engine> _engine(Uri wasm) =>
      _engines[wasm.toString()] ??= _Engine.load(wasm);

  @override
  Future<OpenedDatabase> open(String nameOrPath, OpenOptions options) async {
    final _Engine engine = await _engine(
      options.webWasmUri ?? Uri.parse('sqlite3mc.wasm'),
    );
    if (options.key != null && !engine.encrypts) {
      throw StateError(
        'An encryption key was given but ${options.webWasmUri} does not '
        'encrypt: serve sqlite3mc.wasm (dart run b012_data:setup_web).',
      );
    }
    _askPersistence();
    final String path = nameOrPath.startsWith('/')
        ? nameOrPath
        : '/$nameOrPath';
    final _WebLock lock = await _WebLock.acquire('b012_data:$path');
    try {
      final String? key = options.key;
      if (key != null && _isPlain(engine.fs, path)) {
        throw StateError(
          'The database $path is not encrypted: call '
          'DataAccess.instance.encryptDatabase(key) to encrypt it in place.',
        );
      }
      final CommonDatabase db = engine.sqlite.open(path, vfs: engine.vfs);
      if (key != null) {
        try {
          db.execute('PRAGMA key = ${sqlLiteral(key)}');
          db.select('SELECT count(*) FROM sqlite_master');
        } catch (_) {
          db.close();
          throw StateError(
            'The encryption key does not open $path (wrong key, or not a database).',
          );
        }
      }
      final WebExecutor executor = WebExecutor(db, engine.fs);
      return OpenedDatabase(
        executor: executor,
        path: path,
        close: () async {
          await executor.close();
          await lock.release();
        },
      );
    } catch (_) {
      await lock.release();
      rethrow;
    }
  }

  void _askPersistence() {
    if (_persistAsked) return;
    _persistAsked = true;
    try {
      web.window.navigator.storage.persist().toDart.ignore();
    } catch (_) {
      // Best effort: some browsers do not offer it.
    }
  }

  @override
  Future<Database> openRaw(String path) =>
      throw UnsupportedError('openDB is not available in a browser.');

  @override
  Future<void> delete(String path) async {
    final _Engine engine = await _engine(Uri.parse('sqlite3mc.wasm'));
    final String full = path.startsWith('/') ? path : '/$path';
    for (final String file in <String>[full, '$full-journal', '$full-wal']) {
      if (engine.fs.xAccess(file, 0) != 0) engine.fs.xDelete(file, 0);
    }
    await engine.fs.flush();
  }

  static bool _isPlain(IndexedDbFileSystem fs, String path) {
    if (fs.xAccess(path, 0) == 0) return false;
    final VirtualFileSystemFile file = fs
        .xOpen(Sqlite3Filename(path), SqlFlag.SQLITE_OPEN_READONLY)
        .file;
    try {
      if (file.xFileSize() < sqliteHeader.length) return false;
      final Uint8List head = Uint8List(sqliteHeader.length);
      file.xRead(head, 0);
      return isPlainSqlite(head);
    } finally {
      file.xClose();
    }
  }

  @override
  Future<void> encryptInPlace(String name, String key) async {
    final _Engine engine = await _engine(Uri.parse('sqlite3mc.wasm'));
    final String path = name.startsWith('/') ? name : '/$name';
    if (!_isPlain(engine.fs, path)) return;
    final _WebLock lock = await _WebLock.acquire('b012_data:$path');
    try {
      final CommonDatabase db = engine.sqlite.open(path, vfs: engine.vfs);
      try {
        db.execute('PRAGMA rekey = ${sqlLiteral(key)}');
      } finally {
        db.close();
      }
      await engine.fs.flush();
    } finally {
      await lock.release();
    }
    if (_isPlain(engine.fs, path)) {
      throw StateError('The database $path could not be encrypted.');
    }
  }

  @override
  Future<String?> readPointer() async =>
      web.window.localStorage.getItem(_pointerKey);

  @override
  Future<void> writePointer(String name) async =>
      web.window.localStorage.setItem(_pointerKey, name);
}

/// A loaded WebAssembly SQLite with the IndexedDB file system registered.
class _Engine {
  _Engine(this.sqlite, this.fs, this.encrypts)
    : vfs = encrypts
          ? 'multipleciphers-${WebBackend._vfsName}'
          : WebBackend._vfsName;

  final WasmSqlite3 sqlite;
  final IndexedDbFileSystem fs;

  /// Whether this module is SQLite3MultipleCiphers.
  final bool encrypts;

  /// The VFS to open databases with: SQLite3MultipleCiphers only accepts a
  /// key through its own wrapper of the IndexedDB file system.
  final String vfs;

  static Future<_Engine> load(Uri wasm) async {
    final WasmSqlite3 sqlite = await WasmSqlite3.loadFromUrl(wasm);
    final IndexedDbFileSystem fs = await IndexedDbFileSystem.open(
      dbName: WebBackend._idbName,
      vfsName: WebBackend._vfsName,
    );
    sqlite.registerVirtualFileSystem(fs, makeDefault: false);
    bool encrypts;
    try {
      final CommonDatabase probe = sqlite.openInMemory();
      probe.select('SELECT sqlite3mc_version()');
      probe.close();
      encrypts = true;
    } catch (_) {
      encrypts = false;
    }
    return _Engine(sqlite, fs, encrypts);
  }
}

/// [SqlExecutor] over a WebAssembly database. Operations run one at a time;
/// a transaction holds the connection until it ends; every write is flushed
/// to IndexedDB before its future completes.
class WebExecutor implements SqlExecutor {
  WebExecutor(this._db, this._fs);

  final CommonDatabase _db;
  final IndexedDbFileSystem _fs;
  Future<void> _tail = Future<void>.value();
  bool _closed = false;

  Future<T> _exclusive<T>(Future<T> Function() body) {
    final Completer<void> done = Completer<void>();
    final Future<void> previous = _tail;
    _tail = done.future;
    return previous
        .then((_) {
          if (_closed) throw StateError('The database is closed.');
          return body();
        })
        .whenComplete(done.complete);
  }

  @override
  Future<List<Map<String, Object?>>> select(
    String sql, [
    List<Object?> args = const <Object?>[],
  ]) => _exclusive(() async => _select(_db, sql, args));

  @override
  Future<int> insert(String sql, [List<Object?> args = const <Object?>[]]) =>
      _exclusive(() async {
        _db.execute(sql, args);
        final int id = _db.lastInsertRowId;
        await _fs.flush();
        return id;
      });

  @override
  Future<int> change(String sql, [List<Object?> args = const <Object?>[]]) =>
      _exclusive(() async {
        _db.execute(sql, args);
        final int changed = _db.updatedRows;
        await _fs.flush();
        return changed;
      });

  @override
  Future<void> execute(String sql, [List<Object?> args = const <Object?>[]]) =>
      _exclusive(() async {
        _db.execute(sql, args);
        await _fs.flush();
      });

  @override
  Future<T> transaction<T>(Future<T> Function(SqlExecutor tx) action) =>
      _exclusive(() async {
        _db.execute('BEGIN IMMEDIATE');
        try {
          final T result = await action(_WebTransaction(_db));
          _db.execute('COMMIT');
          await _fs.flush();
          return result;
        } catch (_) {
          if (!_db.autocommit) _db.execute('ROLLBACK');
          rethrow;
        }
      });

  Future<void> close() => _exclusive(() async {
    _db.close();
    _closed = true;
    await _fs.flush();
  });
}

List<Map<String, Object?>> _select(
  CommonDatabase db,
  String sql,
  List<Object?> args,
) => db
    .select(sql, args)
    .map((Row row) => Map<String, Object?>.of(row))
    .toList();

/// The executor given to a transaction body: same connection, no lock (the
/// transaction holds it), flushed once at commit.
class _WebTransaction implements SqlExecutor {
  _WebTransaction(this._db);

  final CommonDatabase _db;

  @override
  Future<List<Map<String, Object?>>> select(
    String sql, [
    List<Object?> args = const <Object?>[],
  ]) async => _select(_db, sql, args);

  @override
  Future<int> insert(
    String sql, [
    List<Object?> args = const <Object?>[],
  ]) async {
    _db.execute(sql, args);
    return _db.lastInsertRowId;
  }

  @override
  Future<int> change(
    String sql, [
    List<Object?> args = const <Object?>[],
  ]) async {
    _db.execute(sql, args);
    return _db.updatedRows;
  }

  @override
  Future<void> execute(
    String sql, [
    List<Object?> args = const <Object?>[],
  ]) async => _db.execute(sql, args);

  @override
  Future<T> transaction<T>(Future<T> Function(SqlExecutor tx) action) =>
      action(this);
}

/// An exclusive Web Lock held while a database is open.
class _WebLock {
  _WebLock._(this._release, this._released);

  final Completer<void>? _release;

  /// Completes once the browser has actually released the lock.
  final Future<void> _released;

  static Future<_WebLock> acquire(String name) async {
    final web.LockManager? locks = _locks();
    if (locks == null) return _WebLock._(null, Future<void>.value());
    final Completer<bool> granted = Completer<bool>();
    final Completer<void> release = Completer<void>();
    final Future<void> released = locks
        .request(
          name,
          web.LockOptions(ifAvailable: true),
          ((web.Lock? lock) {
            if (lock == null) {
              granted.complete(false);
              return null;
            }
            granted.complete(true);
            return release.future.toJS;
          }).toJS,
        )
        .toDart
        .then((_) {}, onError: (Object _) {});
    if (!await granted.future) {
      throw StateError(
        'The database is already open in another tab of this browser. '
        'Close the other tab, then try again.',
      );
    }
    return _WebLock._(release, released);
  }

  static web.LockManager? _locks() {
    try {
      return web.window.navigator.locks;
    } catch (_) {
      return null;
    }
  }

  /// Releases the lock and waits until the browser has released it, so that
  /// the same tab can open the database again at once.
  Future<void> release() {
    final Completer<void>? r = _release;
    if (r != null && !r.isCompleted) r.complete();
    return _released;
  }
}

/// The backend of this platform.
Backend createBackend() => WebBackend();
