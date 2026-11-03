import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:sqflite_common/sqlite_api.dart' show Database;
import 'package:sqlite3/wasm.dart';
import 'package:web/web.dart' as web;

import '../encryption.dart';
import '../executor.dart';

/// Browser backend over `package:sqlite3` (the 2.1 trials showed that
/// `sqflite_common_ffi_web` can neither encrypt nor wait for a write to be
/// stored).
///
/// * SQLite runs as WebAssembly (`sqlite3mc.wasm` by default, which also
///   opens unencrypted databases), loaded from the application's `web/`
///   folder — one module, the configured one, for everything.
/// * Databases live in IndexedDB (`IndexedDbFileSystem`, database
///   `b012_data`), opened without automatic writes: every write is stored by
///   an explicit flush before its future completes.
/// * One tab at a time: a Web Lock is held while the database is open, and
///   the storage is read only once the lock is held, so a tab never works on
///   a copy older than another tab's last writes. A second tab gets a clear
///   error.
class WebBackend implements Backend {
  static const String _idbName = 'b012_data';
  static const String _pointerKey = 'b012_data.dbName';

  final Map<String, Future<_Module>> _modules = <String, Future<_Module>>{};
  int _vfsCount = 0;
  bool _persistAsked = false;

  Future<_Module> _module(OpenOptions options) {
    final Uri uri = options.webWasmUri ?? Uri.parse('sqlite3mc.wasm');
    return _modules[uri.toString()] ??= _Module.load(uri).catchError((
      Object e,
    ) {
      _modules.remove(uri.toString());
      throw e;
    });
  }

  static String _full(String nameOrPath) =>
      nameOrPath.startsWith('/') ? nameOrPath : '/$nameOrPath';

  /// Takes the lock of [path], then reads the IndexedDB storage afresh.
  Future<_Session> _session(String path, OpenOptions options) async {
    final _Module module = await _module(options);
    final _WebLock lock = await _WebLock.acquire('b012_data:$path');
    try {
      final String vfsName = 'b012_idb_${_vfsCount++}';
      final IndexedDbFileSystem fs = await IndexedDbFileSystem.open(
        dbName: _idbName,
        vfsName: vfsName,
        writeAutomatically: false,
      );
      module.sqlite.registerVirtualFileSystem(fs, makeDefault: false);
      return _Session(module, fs, vfsName, lock);
    } catch (_) {
      await lock.release();
      rethrow;
    }
  }

  @override
  Future<OpenedDatabase> open(String nameOrPath, OpenOptions options) async {
    final String? key = options.key;
    final _Module module = await _module(options);
    if (key != null && !module.encrypts) {
      throw StateError(
        'An encryption key was given but the WebAssembly SQLite does not '
        'encrypt: serve sqlite3mc.wasm (dart run b012_data:setup_web).',
      );
    }
    _askPersistence();
    final String path = _full(nameOrPath);
    final _Session session = await _session(path, options);
    try {
      if (key == null && _isProtected(session.fs, path)) {
        throw StateError(keyNeeded(path));
      }
      if (key != null && _isPlain(session.fs, path)) {
        throw StateError(
          'The database $path is not encrypted: call '
          'DataAccess.instance.encryptDatabase(key) to encrypt it in place.',
        );
      }
      final CommonDatabase db = module.sqlite.open(path, vfs: session.vfs);
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
      final WebExecutor executor = WebExecutor(db, session.fs);
      return OpenedDatabase(
        executor: executor,
        path: path,
        close: () async {
          await executor.close();
          await session.end();
        },
      );
    } catch (_) {
      await session.end();
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
  Future<void> delete(String path, OpenOptions options) async {
    final String full = _full(path);
    final _Session session = await _session(full, options);
    try {
      for (final String file in <String>[full, '$full-journal', '$full-wal']) {
        if (session.fs.xAccess(file, 0) != 0) session.fs.xDelete(file, 0);
      }
    } finally {
      await session.end();
    }
  }

  static Uint8List? _head(IndexedDbFileSystem fs, String path) {
    if (fs.xAccess(path, 0) == 0) return null;
    final VirtualFileSystemFile file = fs
        .xOpen(Sqlite3Filename(path), SqlFlag.SQLITE_OPEN_READONLY)
        .file;
    try {
      if (file.xFileSize() < sqliteHeader.length) return null;
      final Uint8List head = Uint8List(sqliteHeader.length);
      file.xRead(head, 0);
      return head;
    } finally {
      file.xClose();
    }
  }

  static bool _isProtected(IndexedDbFileSystem fs, String path) {
    final Uint8List? head = _head(fs, path);
    return head != null && !isPlainSqlite(head);
  }

  static bool _isPlain(IndexedDbFileSystem fs, String path) {
    final Uint8List? head = _head(fs, path);
    return head != null && isPlainSqlite(head);
  }

  @override
  Future<void> encryptInPlace(
    String name,
    String key,
    OpenOptions options,
  ) async {
    final _Module module = await _module(options);
    if (!module.encrypts) {
      throw StateError(
        'The WebAssembly SQLite does not encrypt: serve sqlite3mc.wasm '
        '(dart run b012_data:setup_web).',
      );
    }
    final String path = _full(name);
    final _Session session = await _session(path, options);
    try {
      if (!_isPlain(session.fs, path)) return;
      final CommonDatabase db = module.sqlite.open(path, vfs: session.vfs);
      try {
        db.execute('PRAGMA rekey = ${sqlLiteral(key)}');
      } finally {
        db.close();
      }
      await session.fs.flush();
      if (_isPlain(session.fs, path)) {
        throw StateError('The database $path could not be encrypted.');
      }
    } finally {
      await session.end();
    }
  }

  @override
  Future<String?> readPointer() async =>
      web.window.localStorage.getItem(_pointerKey);

  @override
  Future<void> writePointer(String name) async =>
      web.window.localStorage.setItem(_pointerKey, name);
}

/// A loaded WebAssembly SQLite.
class _Module {
  _Module(this.sqlite, this.encrypts);

  final WasmSqlite3 sqlite;

  /// Whether this module is SQLite3MultipleCiphers.
  final bool encrypts;

  static Future<_Module> load(Uri wasm) async {
    final WasmSqlite3 sqlite = await WasmSqlite3.loadFromUrl(wasm);
    // A WebAssembly SQLite has no file system of its own: an in-memory one
    // is the default (the encryption probe below needs it).
    sqlite.registerVirtualFileSystem(InMemoryFileSystem(), makeDefault: true);
    bool encrypts;
    try {
      final CommonDatabase probe = sqlite.openInMemory();
      probe.select('SELECT sqlite3mc_version()');
      probe.close();
      encrypts = true;
    } catch (_) {
      encrypts = false;
    }
    return _Module(sqlite, encrypts);
  }
}

/// A lock and a fresh view of the IndexedDB storage, for one opening.
class _Session {
  _Session(this.module, this.fs, this.vfsName, this.lock);

  final _Module module;
  final IndexedDbFileSystem fs;
  final String vfsName;
  final _WebLock lock;
  bool _ended = false;

  /// SQLite3MultipleCiphers only accepts a key through its own wrapper of
  /// the storage.
  String get vfs => module.encrypts ? 'multipleciphers-$vfsName' : vfsName;

  /// Stores what is pending, closes the storage, releases the lock.
  Future<void> end() async {
    if (_ended) return;
    _ended = true;
    try {
      await fs.flush();
      module.sqlite.unregisterVirtualFileSystem(fs);
      await fs.close();
    } finally {
      await lock.release();
    }
  }
}

/// [SqlExecutor] over a WebAssembly database. Operations run one at a time;
/// a transaction holds the connection until it ends; everything is flushed
/// to IndexedDB before a future completes.
class WebExecutor implements SqlExecutor {
  WebExecutor(this._db, this._fs);

  final CommonDatabase _db;
  final IndexedDbFileSystem _fs;
  Future<void> _tail = Future<void>.value();
  bool _closed = false;

  Future<T> _exclusive<T>(T Function() body) {
    final Completer<void> done = Completer<void>();
    final Future<void> previous = _tail;
    _tail = done.future;
    return previous
        .then((_) async {
          if (_closed) throw StateError('The database is closed.');
          final T result = body();
          await _fs.flush();
          return result;
        })
        .whenComplete(done.complete);
  }

  @override
  Future<List<Map<String, Object?>>> select(
    String sql, [
    List<Object?> args = const <Object?>[],
  ]) => _exclusive(() => _select(_db, sql, args));

  @override
  Future<int> insert(String sql, [List<Object?> args = const <Object?>[]]) =>
      _exclusive(() {
        _db.execute(sql, args);
        return _db.lastInsertRowId;
      });

  @override
  Future<int> change(String sql, [List<Object?> args = const <Object?>[]]) =>
      _exclusive(() {
        _db.execute(sql, args);
        return _db.updatedRows;
      });

  @override
  Future<void> execute(String sql, [List<Object?> args = const <Object?>[]]) =>
      _exclusive(() => _db.execute(sql, args));

  @override
  Future<T> transaction<T>(Future<T> Function(SqlExecutor tx) action) {
    final Completer<void> done = Completer<void>();
    final Future<void> previous = _tail;
    _tail = done.future;
    return previous
        .then((_) async {
          if (_closed) throw StateError('The database is closed.');
          _db.execute('BEGIN IMMEDIATE');
          try {
            final T result = await action(_WebTransaction(_db));
            _db.execute('COMMIT');
            await _fs.flush();
            return result;
          } catch (_) {
            if (!_db.autocommit) _db.execute('ROLLBACK');
            await _fs.flush();
            rethrow;
          }
        })
        .whenComplete(done.complete);
  }

  Future<void> close() => _exclusive(() {
    _db.close();
    _closed = true;
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
/// transaction holds it), flushed once at the end.
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
