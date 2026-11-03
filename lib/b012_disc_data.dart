import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import 'package:b012_data/b012_sqlflite_easy.dart';

import 'src/native/atomic_file.dart';
import 'src/native/locations.dart';
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

/// High-level API for reading/writing files on disk, abstracting away the
/// per-platform differences (path separators, default root directory,
/// hidden-directory conventions, ...).
///
/// Files are read and written asynchronously; a file is written all at once
/// (a reader never sees half of it), and a file *name* can never point
/// outside [filesPath].
///
/// Access the singleton through [DiscData.instance].
class DiscData {
  DiscData._internal();

  /// Global singleton instance.
  static final DiscData instance = DiscData._internal();

  /// Platform path separator (`'\'` on Windows, `'/'` elsewhere).
  final String pathJoin = !kIsWeb && Platform.isWindows ? r'\' : '/';

  /// Root directory for the current application. Equivalent to
  /// `getApplicationDocumentsDirectory().path`.
  Future<String> get rootPath => Locations.instance.documentsDir;

  /// Directory holding the `dbName` file of [DataAccess.changeDB].
  ///
  /// * Android, iOS, macOS: `<parent of Documents>/databases`, as before.
  /// * Windows, Linux: `<application support>/databases`, where the
  ///   databases of a new installation live too.
  Future<String> get databasesPath => Locations.instance.databasesDir;

  /// Directory used to store user-facing files saved by the package.
  ///
  /// * Android, iOS, macOS: `<parent of Documents>/files`, as before.
  /// * Windows, Linux: `<application support>/files` for a new installation;
  ///   an application that kept its 2.0.3 database keeps its 2.0.3 folder
  ///   (`<parent of Documents>/.files` on Windows, `files` on Linux). Files
  ///   saved there by 2.0.3 remain readable by name either way.
  Future<String> get filesPath => Locations.instance.filesDir;

  /// Forgets the cached folders (tests only).
  @visibleForTesting
  void debugResetPaths() => Locations.instance.reset();

  /// Returns `true` if the file identified by [fileName] (relative to
  /// [filesPath]) or by the absolute [path] exists on disk.
  Future<bool> checkFileExists({String? fileName, String? path}) async =>
      (await _existing(fileName, path)).exists();

  /// Returns the parent directory of [path], computed by stripping the last
  /// component from the path.
  ///
  /// Example:
  /// ```dart
  /// getParentDir('/flutter/app/dir/test'); // '/flutter/app/dir'
  /// ```
  String getParentDir(String path) =>
      (path.split(pathJoin)..removeLast()).join(pathJoin);

  /// Writes [data] to disk.
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
  ///
  /// Returns the file name actually used, or `null` when [data] is null /
  /// empty.
  Future<String?> saveDataToDisc(
    Object? data,
    DataType dataType, {
    String? takeThisName,
    String? path,
    bool recursive = false,
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

    if (!kIsWeb && Platform.isWindows) fileName = fileName.replaceAll(':', '');

    final File file;
    final String? validated = validatePath(path);
    if (validated != null) {
      file = File(validated);
      if (!recursive && !await file.parent.exists()) {
        throw PathNotFoundException(
          validated,
          const OSError('The parent directory does not exist'),
          'Cannot create file',
        );
      }
    } else {
      file = File(_inFolder(await filesPath, fileName));
    }
    await writeAtomically(file, _bytesOf(data, dataType));
    return fileName;
  }

  /// Appends [data] to an existing file on disk.
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

    final File file = await _existing(fileName, path);
    if (!await file.exists()) return;
    await file.writeAsBytes(
      _bytesOf(data, dataType),
      mode: FileMode.append,
      flush: true,
    );
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
  Future<Uint8List?> readFileAsBytes({String? fileName, String? path}) async {
    final File file = await _existing(fileName, path);
    if (!await file.exists()) return null;
    return file.readAsBytes();
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

  /// Returns the file handle, or `null` when the file does not exist.
  Future<File?> getFile({String? fileName, String? path}) async {
    final File file = await _existing(fileName, path);
    return await file.exists() ? file : null;
  }

  /// Deletes a file on disk.
  ///
  /// Returns `true` if the file did not exist or was successfully deleted,
  /// and `false` if the deletion failed.
  Future<bool> deleteFile({String? fileName, String? path}) async {
    final File file = await _existing(fileName, path);
    if (!await file.exists()) return true;
    try {
      await file.delete();
      return !await file.exists();
    } on FileSystemException catch (e, s) {
      debugPrint('deleteFile failed: $e\n$s');
      return false;
    }
  }

  /// Loads an image from disk and returns an [Image] widget.
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

  /// [name] inside [folder]; a name that would leave it throws.
  String _inFolder(String folder, String name) {
    if (name.isEmpty) return folder;
    final String target = p.normalize(p.join(folder, name));
    if (!p.isWithin(folder, target)) {
      throw ArgumentError.value(name, 'fileName', 'must stay inside $folder');
    }
    return target;
  }

  /// The file designated by an explicit [path], or by [fileName] in
  /// [filesPath] — or, when it is not there, in the 2.0.3 folder.
  Future<File> _existing(String? fileName, String? path) async {
    final String? validated = validatePath(path);
    if (validated != null) return File(validated);
    final String name = fileName ?? '';
    final File primary = File(_inFolder(await filesPath, name));
    if (name.isEmpty || await primary.exists()) return primary;
    final String? fallback = await Locations.instance.fallbackFilesDir;
    if (fallback == null) return primary;
    final File old = File(_inFolder(fallback, name));
    return await old.exists() ? old : primary;
  }
}

/// Convenience probe that pings `google.com` to check for internet access.
///
/// Returns `false` when:
/// * the host cannot be resolved (no DNS),
/// * resolution succeeds but the result is empty,
/// * any [SocketException] is thrown during the lookup.
Future<bool> get isInternetAvailable async {
  try {
    final List<InternetAddress> result = await InternetAddress.lookup(
      'google.com',
    );
    return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
  } on SocketException {
    return false;
  }
}
