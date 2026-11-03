import 'dart:async';
import 'dart:io' show File;
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:web/web.dart' as web;

import '../files_api.dart';

/// [FileStore] in IndexedDB (database `b012_data_files`, store `files`),
/// apart from the SQLite database so that files are not held in memory.
/// Writes use strict durability: they are on disk when they complete.
class WebFileStore implements FileStore {
  static const String _dbName = 'b012_data_files';
  static const String _store = 'files';
  static const String _files = '/files';

  Future<web.IDBDatabase>? _opening;

  @override
  String get separator => '/';

  @override
  Future<String> get rootPath async => '/';

  @override
  Future<String> get databasesPath async => '/databases';

  @override
  Future<String> get filesPath async => _files;

  @override
  void reset() {}

  Future<web.IDBDatabase> _db() => _opening ??= _open();

  Future<web.IDBDatabase> _open() {
    final Completer<web.IDBDatabase> done = Completer<web.IDBDatabase>();
    final web.IDBOpenDBRequest request = web.window.indexedDB.open(_dbName, 1);
    request.onupgradeneeded = ((web.Event _) {
      final web.IDBDatabase db = request.result! as web.IDBDatabase;
      if (!db.objectStoreNames.contains(_store)) db.createObjectStore(_store);
    }).toJS;
    request.onsuccess = ((web.Event _) {
      done.complete(request.result! as web.IDBDatabase);
    }).toJS;
    request.onerror = ((web.Event _) {
      done.completeError(StateError('IndexedDB: ${request.error?.message}'));
    }).toJS;
    return done.future;
  }

  /// The IndexedDB key of a file.
  String _key(String? fileName, String? path) {
    if (path != null) return 'path:$path';
    final String name = fileName ?? '';
    final String target = p.posix.normalize(p.posix.join(_files, name));
    if (name.isNotEmpty && !p.posix.isWithin(_files, target)) {
      throw ArgumentError.value(name, 'fileName', 'must stay inside $_files');
    }
    return target;
  }

  Future<T> _run<T>(
    String mode,
    T Function(web.IDBObjectStore store, void Function(T) setResult) body,
  ) async {
    final web.IDBDatabase db = await _db();
    final web.IDBTransaction tx = db.transaction(
      _store.toJS,
      mode,
      web.IDBTransactionOptions(durability: 'strict'),
    );
    final Completer<T> done = Completer<T>();
    late T result;
    void setResult(T value) => result = value;
    result = body(tx.objectStore(_store), setResult);
    tx.oncomplete = ((web.Event _) => done.complete(result)).toJS;
    tx.onerror = ((web.Event _) {
      if (!done.isCompleted) {
        done.completeError(StateError('IndexedDB: ${tx.error?.message}'));
      }
    }).toJS;
    tx.onabort = ((web.Event _) {
      if (!done.isCompleted) {
        done.completeError(StateError('IndexedDB: transaction aborted'));
      }
    }).toJS;
    return done.future;
  }

  static Uint8List? _bytes(JSAny? value) {
    if (value == null) return null;
    if (value.isA<JSArrayBuffer>()) {
      return (value as JSArrayBuffer).toDart.asUint8List();
    }
    if (value.isA<JSUint8Array>()) return (value as JSUint8Array).toDart;
    return null;
  }

  @override
  Future<Uint8List?> read({String? fileName, String? path}) {
    final String key = _key(fileName, path);
    return _run<Uint8List?>('readonly', (
      web.IDBObjectStore store,
      void Function(Uint8List?) setResult,
    ) {
      final web.IDBRequest request = store.get(key.toJS);
      request.onsuccess = ((web.Event _) => setResult(
        _bytes(request.result),
      )).toJS;
      return null;
    });
  }

  @override
  Future<bool> exists({String? fileName, String? path}) async =>
      (await read(fileName: fileName, path: path)) != null;

  @override
  Future<void> write(
    List<int> bytes, {
    String? fileName,
    String? path,
    bool recursive = false,
  }) {
    final String key = _key(fileName, path);
    final Uint8List data = Uint8List.fromList(bytes);
    return _run<void>('readwrite', (
      web.IDBObjectStore store,
      void Function(void) setResult,
    ) {
      store.put(data.buffer.toJS, key.toJS);
    });
  }

  @override
  Future<void> append(List<int> bytes, {String? fileName, String? path}) {
    final String key = _key(fileName, path);
    return _run<void>('readwrite', (
      web.IDBObjectStore store,
      void Function(void) setResult,
    ) {
      final web.IDBRequest request = store.get(key.toJS);
      request.onsuccess = ((web.Event _) {
        final Uint8List? old = _bytes(request.result);
        if (old == null) return;
        final Uint8List joined = Uint8List(old.length + bytes.length)
          ..setAll(0, old)
          ..setAll(old.length, bytes);
        store.put(joined.buffer.toJS, key.toJS);
      }).toJS;
    });
  }

  @override
  Future<bool> delete({String? fileName, String? path}) async {
    final String key = _key(fileName, path);
    await _run<void>('readwrite', (
      web.IDBObjectStore store,
      void Function(void) setResult,
    ) {
      store.delete(key.toJS);
    });
    return true;
  }

  @override
  Future<File?> file({String? fileName, String? path}) async => null;

  @override
  Future<bool> internetAvailable() async => web.window.navigator.onLine;

  @override
  Future<List<String>> listNames() => _run<List<String>>('readonly', (
    web.IDBObjectStore store,
    void Function(List<String>) setResult,
  ) {
    final web.IDBRequest request = store.getAllKeys();
    request.onsuccess = ((web.Event _) {
      final List<String> names = <String>[];
      for (final JSAny? key in (request.result! as JSArray<JSAny?>).toDart) {
        final String k = (key! as JSString).toDart;
        if (k.startsWith('$_files/')) names.add(k.substring(_files.length + 1));
      }
      setResult(names);
    }).toJS;
    return <String>[];
  });
}

FileStore createFileStore() => WebFileStore();
