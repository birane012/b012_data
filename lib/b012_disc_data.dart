import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, FileSystemException;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:b012_data/b012_sqlflite_easy.dart';

import 'src/crypto_files.dart';
import 'src/encryption.dart';
import 'src/files.dart';
import 'src/files_api.dart';
import 'src/sql.dart' show columnRef;

/// Describes the kind of data stored in / read from a file on disk.
enum DataType {
  /// Plain text (UTF-8 string).
  text,

  /// Base64-encoded string that should be decoded before being written.
  base64,

  /// Raw binary data (`Uint8List`).
  bytes,
}

/// High-level API for reading/writing files, abstracting away the
/// per-platform differences (path separators, default root directory,
/// hidden-directory conventions, browser storage, ...).
///
/// Files are read and written asynchronously; a file is written all at once
/// (a reader never sees half of it), and a file *name* can never point
/// outside [filesPath].
///
/// In a browser, files live in IndexedDB, next to the database: the methods
/// that read and write bytes, text or base64 work the same; [getFile], which
/// returns a `dart:io` file, returns `null`.
///
/// Access the singleton through [DiscData.instance].
class DiscData {
  DiscData._internal() {
    EncryptionHooks.encryptExistingFiles = _encryptExisting;
  }

  /// Global singleton instance.
  static final DiscData instance = DiscData._internal();

  final FileStore _store = createFileStore();

  /// Writes, appends and deletes run one at a time per file, so concurrent
  /// calls never lose each other's content.
  final Map<String, Future<void>> _tails = <String, Future<void>>{};

  /// Names of the files saved by name since 2.1 (loaded once).
  Set<String>? _names;

  Future<T> _locked<T>(String key, Future<T> Function() body) {
    final Future<void> previous = _tails[key] ?? Future<void>.value();
    final Completer<void> done = Completer<void>();
    _tails[key] = done.future;
    return previous.then((_) => body()).whenComplete(() {
      done.complete();
      if (identical(_tails[key], done.future)) _tails.remove(key);
    });
  }

  static String _lockKey(String? fileName, String? path) =>
      path ?? 'name:${fileName ?? ''}';

  Future<Set<String>> _manifest() async {
    final Set<String>? cached = _names;
    if (cached != null) return cached;
    final Uint8List? bytes = await _store.read(
      path: await _store.manifestPath,
      fallback: false,
    );
    final Object? decoded = bytes == null
        ? null
        : jsonDecode(utf8.decode(bytes));
    return _names = decoded is List
        ? decoded.map((Object? e) => e.toString()).toSet()
        : <String>{};
  }

  /// Records (or forgets) [name] in the list of files saved by name.
  Future<void> _record(String name, {required bool saved}) =>
      _locked('manifest', () async {
        final Set<String> names = await _manifest();
        final bool changed = saved ? names.add(name) : names.remove(name);
        if (!changed) return;
        await _store.write(
          utf8.encode(jsonEncode(names.toList()..sort())),
          path: await _store.manifestPath,
          recursive: true,
        );
      });

  /// Platform path separator (`'\'` on Windows, `'/'` elsewhere).
  late final String pathJoin = _store.separator;

  /// Root directory for the current application. Equivalent to
  /// `getApplicationDocumentsDirectory().path` (`/` in a browser).
  Future<String> get rootPath => _store.rootPath;

  /// Directory holding the `dbName` file of [DataAccess.changeDB].
  ///
  /// * Android, iOS, macOS: `<parent of Documents>/databases`, as before.
  /// * Windows, Linux: `<application support>/databases`, where the
  ///   databases of a new installation live too.
  Future<String> get databasesPath => _store.databasesPath;

  /// Directory used to store user-facing files saved by the package.
  ///
  /// * Android, iOS, macOS: `<parent of Documents>/files`, as before.
  /// * Windows, Linux: `<application support>/files` for a new installation;
  ///   an application that kept its 2.0.3 database keeps its 2.0.3 folder
  ///   (`<parent of Documents>/.files` on Windows, `files` on Linux). Files
  ///   saved there by 2.0.3 remain readable by name either way.
  /// * Browser: `/files`, a name space inside IndexedDB.
  Future<String> get filesPath => _store.filesPath;

  /// Forgets the cached folders (tests only).
  @visibleForTesting
  void debugResetPaths() {
    _store.reset();
    _names = null;
  }

  /// Returns `true` if the file identified by [fileName] (relative to
  /// [filesPath]) or by the absolute [path] exists.
  Future<bool> checkFileExists({String? fileName, String? path}) =>
      _store.exists(fileName: fileName, path: validatePath(path));

  /// Returns the parent directory of [path], computed by stripping the last
  /// component from the path.
  ///
  /// Example:
  /// ```dart
  /// getParentDir('/flutter/app/dir/test'); // '/flutter/app/dir'
  /// ```
  String getParentDir(String path) =>
      (path.split(pathJoin)..removeLast()).join(pathJoin);

  /// Writes [data].
  ///
  /// * If [path] is provided, the data is written to that absolute path and
  ///   the file name is derived from it. When [recursive] is `true`, any
  ///   missing parent directory is created; otherwise a
  ///   [FileSystemException] is thrown if the parent directory does not
  ///   exist.
  /// * Otherwise, the file is created inside [filesPath] (created if needed)
  ///   using [takeThisName] as its name, or the current timestamp when
  ///   [takeThisName] is null. A name that would leave [filesPath] (such as
  ///   `../x`) throws an [ArgumentError].
  /// * [dataType] drives how [data] is serialised: `DataType.text` treats it
  ///   as a `String`, `DataType.base64` decodes it and stores the decoded
  ///   bytes, `DataType.bytes` stores it as a `Uint8List`.
  /// * The file is written all at once: a reader sees the old content or the
  ///   new one, never half of it.
  /// * When the database is encrypted ([DataAccess.useEncryptionKey]), a
  ///   file saved by name is encrypted (AES-256-GCM); a file written at an
  ///   explicit [path] (an export, for instance) is written as is unless
  ///   [encrypt] is `true`.
  ///
  /// Returns the file name actually used, or `null` when [data] is null /
  /// empty.
  Future<String?> saveDataToDisc(
    Object? data,
    DataType dataType, {
    String? takeThisName,
    String? path,
    bool recursive = false,
    bool? encrypt,
  }) async {
    if (data == null) return null;
    if (data is String && data.isEmpty) return null;
    if (data is List && data.isEmpty) return null;

    String fileName;
    if (path != null) {
      fileName = path.split(pathJoin).last;
    } else {
      fileName = takeThisName ?? DateTime.now().toIso8601String();
    }

    if (pathJoin == r'\') fileName = fileName.replaceAll(':', '');

    final String? validated = validatePath(path);
    final List<int> bytes = await _seal(
      _bytesOf(data, dataType),
      encrypt ?? validated == null,
    );
    await _locked(
      _lockKey(fileName, validated),
      () => _store.write(
        bytes,
        fileName: validated == null ? fileName : null,
        path: validated,
        recursive: recursive,
      ),
    );
    if (validated == null) await _record(fileName, saved: true);
    return fileName;
  }

  /// Appends [data] to an existing file.
  ///
  /// * When [path] is provided it takes precedence over [fileName].
  /// * Otherwise the file is looked up inside [filesPath] using [fileName].
  /// * [dataType] drives how [data] is appended: strings are appended as
  ///   text, base64 strings are decoded first, bytes are appended as-is.
  ///
  /// Does nothing when [data] is null/empty or when the target file does
  /// not exist.
  Future<void> appendDataToFile(
    Object? data,
    DataType dataType, {
    String? fileName,
    String? path,
  }) async {
    if (data == null) return;
    if (data is String && data.isEmpty) return;
    if (data is List && data.isEmpty) return;
    final String? validated = validatePath(path);
    await _locked(_lockKey(fileName, validated), () async {
      // Never through the shared 2.0.3 folder: only this application's file.
      // Only its first bytes are read to know whether it is encrypted.
      final Uint8List? head = await _store.readHead(
        fileMagic.length,
        fileName: fileName,
        path: validated,
      );
      if (head == null) return;
      if (!hasFileMagic(head)) {
        await _store.append(
          _bytesOf(data, dataType),
          fileName: fileName,
          path: validated,
        );
        return;
      }
      final Uint8List clear = await _open(
        (await _store.read(
          fileName: fileName,
          path: validated,
          fallback: false,
        ))!,
      );
      await _store.write(
        await _seal(<int>[...clear, ..._bytesOf(data, dataType)], true),
        fileName: validated == null ? fileName : null,
        path: validated,
        recursive: true,
      );
    });
  }

  /// [bytes] encrypted when [wanted] and a key is in use.
  Future<List<int>> _seal(List<int> bytes, bool wanted) async {
    if (!wanted) return bytes;
    final Uint8List? key = await EncryptionHooks.fileKey?.call();
    return key == null ? bytes : sealFile(bytes, key);
  }

  /// The clear content of an encrypted file.
  Future<Uint8List> _open(Uint8List sealed) async {
    final Uint8List? key = await EncryptionHooks.fileKey?.call();
    if (key == null) {
      throw StateError(
        'This file is encrypted: set the key with '
        'DataAccess.instance.useEncryptionKey first.',
      );
    }
    try {
      return await openFile(sealed, key);
    } catch (_) {
      throw StateError(
        'This file was encrypted with another key (by another database, or '
        'altered since): it cannot be read with the database open now.',
      );
    }
  }

  /// Encrypts the unencrypted files saved by name: those of the list kept
  /// since 2.1, plus [alsoFiles]. Nothing else is touched.
  Future<void> _encryptExisting(Iterable<String> alsoFiles) async {
    final Uint8List? key = await EncryptionHooks.fileKey?.call();
    if (key == null) return;
    final Set<String> names = <String>{...await _manifest(), ...alsoFiles};
    for (final String name in names) {
      await _locked(_lockKey(name, null), () async {
        final Uint8List? bytes = await _store.read(
          fileName: name,
          fallback: false,
        );
        if (bytes == null || isEncryptedFile(bytes)) return;
        await _store.write(await sealFile(bytes, key), fileName: name);
      });
      await _record(name, saved: true);
    }
  }

  /// Normalizes a file system [path] so it can be safely consumed by `dart:io`.
  ///
  /// * Returns `null` when [path] is `null` or empty.
  /// * Prepends a leading `/` on non-Windows platforms when missing.
  /// * Removes a single trailing separator (`/` or `\\`).
  /// * Collapses repeated separators into a single platform-specific one.
  String? validatePath(String? path) {
    if (path == null || path.isEmpty) return null;

    String normalized = path;
    if (pathJoin == '/' && !normalized.startsWith('/')) {
      normalized = '/$normalized';
    }

    if (normalized.endsWith('/') || normalized.endsWith(r'\')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }

    return normalized.replaceAll(RegExp(r'[/\\]+'), pathJoin);
  }

  /// Reads the file and returns its content encoded as a Base64 string.
  /// Returns `null` when the file does not exist.
  Future<String?> readFileAsBase64({String? fileName, String? path}) async {
    final Uint8List? bytes = await readFileAsBytes(
      fileName: fileName,
      path: path,
    );
    return bytes == null ? null : base64Encode(bytes);
  }

  /// Reads the file and returns its raw bytes.
  /// Returns `null` when the file does not exist.
  ///
  /// An encrypted file is decrypted (the key must be in use).
  Future<Uint8List?> readFileAsBytes({String? fileName, String? path}) async {
    final Uint8List? bytes = await _store.read(
      fileName: fileName,
      path: validatePath(path),
    );
    if (bytes == null || !isEncryptedFile(bytes)) return bytes;
    return _open(bytes);
  }

  /// Reads the file and returns its UTF-8 content.
  /// Returns `null` when the file does not exist.
  Future<String?> readFileAsString({String? fileName, String? path}) async {
    final Uint8List? bytes = await readFileAsBytes(
      fileName: fileName,
      path: path,
    );
    return bytes == null ? null : utf8.decode(bytes);
  }

  /// Returns the file handle, or `null` when the file does not exist
  /// (always `null` in a browser, which has no file system). The file is
  /// returned as stored: encrypted when the database is; read it with
  /// [readFileAsBytes] or [readFileAsString], which decrypt.
  Future<File?> getFile({String? fileName, String? path}) =>
      _store.file(fileName: fileName, path: validatePath(path));

  /// Deletes a file.
  ///
  /// Returns `true` if the file did not exist or was successfully deleted,
  /// and `false` if the deletion failed.
  Future<bool> deleteFile({String? fileName, String? path}) async {
    final String? validated = validatePath(path);
    try {
      final bool deleted = await _locked(
        _lockKey(fileName, validated),
        () => _store.delete(fileName: fileName, path: validated),
      );
      if (validated == null && fileName != null && deleted) {
        await _record(fileName, saved: false);
      }
      return deleted;
    } on FileSystemException catch (e, s) {
      debugPrint('deleteFile failed: $e\n$s');
      return false;
    }
  }

  /// Loads an image and returns an [Image] widget.
  ///
  /// Returns `null` when [imageName] is null/empty or when the file cannot
  /// be found.
  Future<Image?> getImageFromDisc({
    String? imageName,
    String? path,
    BoxFit fit = BoxFit.fill,
  }) async {
    if ((imageName == null || imageName.isEmpty) &&
        (path == null || path.isEmpty)) {
      return null;
    }
    final Uint8List? bytes = await readFileAsBytes(
      fileName: imageName,
      path: path,
    );
    if (bytes == null) return null;
    return Image.memory(bytes, fit: fit);
  }

  /// Loads a file whose name is stored in a column of an SQLite table.
  ///
  /// * [urlColumnName]: name of the column that holds the file name.
  /// * [key] / [value]: condition used to locate the row (`WHERE key = value`,
  ///   the value being bound, never pasted into the SQL).
  /// * [path]: optional directory where the file lives. Defaults to
  ///   [filesPath] when omitted.
  ///
  /// The result is cast to the type parameter [D]:
  /// * `Uint8List` to read the file as bytes.
  /// * `String` to read the file as UTF-8 text.
  ///
  /// Returns `null` when the row or the file cannot be found, or when [D]
  /// is something other than `Uint8List` / `String`.
  Future<D?> getEntityFileOnDisc<D, T>(
    String urlColumnName,
    String key,
    Object value, {
    String? path,
  }) async {
    final List<String> urls = await DataAccess.instance
        .getAColumnFrom<String, T>(
          urlColumnName,
          afterWhere: '${columnRef(key)} = ? LIMIT 1',
          whereArgs: <Object?>[value],
        );
    if (urls.isEmpty) return null;
    final String fileRef = urls.first;

    final String? filePath = path != null ? '$path$pathJoin$fileRef' : null;

    if (D == Uint8List) {
      final Uint8List? bytes = filePath != null
          ? await readFileAsBytes(path: filePath)
          : await readFileAsBytes(fileName: fileRef);
      return bytes as D?;
    }
    if (D == String) {
      final String? text = filePath != null
          ? await readFileAsString(path: filePath)
          : await readFileAsString(fileName: fileRef);
      return text as D?;
    }
    return null;
  }

  List<int> _bytesOf(Object data, DataType dataType) {
    switch (dataType) {
      case DataType.text:
        return utf8.encode(data as String);
      case DataType.base64:
        return base64Decode(data as String);
      case DataType.bytes:
        return data as List<int>;
    }
  }
}

/// Whether internet looks reachable: a DNS lookup of `google.com` on native
/// platforms, the browser's network state in a browser.
///
/// Returns `false` when the host cannot be resolved, when the result is
/// empty, or on a socket error.
Future<bool> get isInternetAvailable =>
    DiscData.instance._store.internetAvailable();
