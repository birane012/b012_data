import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'package:b012_data/b012_sqlflite_easy.dart';

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
/// Access the singleton through [DiscData.instance].
class DiscData {
  DiscData._internal();

  /// Global singleton instance.
  static final DiscData instance = DiscData._internal();

  String? _rootPath;
  String? _databasesPath;
  String? _filesPath;

  /// Platform path separator (`'\'` on Windows, `'/'` elsewhere).
  final String pathJoin = Platform.isWindows ? r'\' : '/';

  /// Default directory name where files saved without an explicit path are
  /// stored.
  ///
  /// On Windows the user has direct access to the folder, so the directory
  /// is prefixed with a dot (`.files`) to discourage accidental deletion.
  final String _defaultFilesDirectory =
      Platform.isWindows ? '.files' : 'files';

  /// Root directory for the current application. Equivalent to
  /// `getApplicationDocumentsDirectory().path`.
  Future<String> get rootPath async {
    _rootPath ??= (await getApplicationDocumentsDirectory()).path;
    return _rootPath!;
  }

  /// Directory where SQLite database files are stored.
  ///
  /// The directory is **not** created on disk automatically - create it from
  /// the client code if you want to make sure it exists before writing.
  Future<String> get databasesPath async {
    _databasesPath ??=
        '${getParentDir(await rootPath)}${pathJoin}databases';
    return _databasesPath!;
  }

  /// Directory used to store user-facing files saved by the package.
  Future<String> get filesPath async {
    _filesPath ??=
        '${getParentDir(await rootPath)}$pathJoin$_defaultFilesDirectory';
    return _filesPath!;
  }

  /// Returns `true` if the file identified by [fileName] (relative to
  /// [filesPath]) or by the absolute [path] exists on disk.
  Future<bool> checkFileExists({String? fileName, String? path}) async {
    final String resolved = await _resolvePath(fileName, path);
    return File(resolved).existsSync();
  }

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
  ///   the file name is derived from it.
  /// * Otherwise, the file is created inside [filesPath] using
  ///   [takeThisName] as its name, or the current timestamp when
  ///   [takeThisName] is null.
  /// * [dataType] drives how [data] is serialised: `DataType.text` treats it
  ///   as a `String`, `DataType.base64` decodes it and stores the decoded
  ///   bytes, `DataType.bytes` stores it as a `Uint8List`.
  /// * When [recursive] is `true`, any missing parent directory is created;
  ///   otherwise a [FileSystemException] is thrown if the parent directory
  ///   does not exist.
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

    if (Platform.isWindows) fileName = fileName.replaceAll(':', '');

    final String resolved = validatePath(path) ??
        '${await filesPath}$pathJoin$fileName';
    final File file = File(resolved);
    file.createSync(recursive: recursive);

    switch (dataType) {
      case DataType.text:
        file.writeAsStringSync(data as String);
        break;
      case DataType.base64:
        file.writeAsBytesSync(base64Decode(data as String));
        break;
      case DataType.bytes:
        file.writeAsBytesSync(data as Uint8List);
        break;
    }
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

    final String resolved = await _resolvePath(fileName, path);
    final File file = File(resolved);
    if (!file.existsSync()) return;

    switch (dataType) {
      case DataType.text:
        file.writeAsStringSync(data as String, mode: FileMode.append);
        break;
      case DataType.base64:
        file.writeAsBytesSync(
          base64Decode(data as String),
          mode: FileMode.append,
        );
        break;
      case DataType.bytes:
        file.writeAsBytesSync(data as Uint8List, mode: FileMode.append);
        break;
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
    if (!Platform.isWindows && !normalized.startsWith('/')) {
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
    final String resolved = await _resolvePath(fileName, path);
    final File file = File(resolved);
    if (!file.existsSync()) return null;
    return base64Encode(file.readAsBytesSync());
  }

  /// Reads the file and returns its raw bytes.
  /// Returns `null` when the file does not exist.
  Future<Uint8List?> readFileAsBytes({String? fileName, String? path}) async {
    final String resolved = await _resolvePath(fileName, path);
    final File file = File(resolved);
    if (!file.existsSync()) return null;
    return file.readAsBytesSync();
  }

  /// Reads the file and returns its UTF-8 content.
  /// Returns `null` when the file does not exist.
  Future<String?> readFileAsString({String? fileName, String? path}) async {
    final String resolved = await _resolvePath(fileName, path);
    final File file = File(resolved);
    if (!file.existsSync()) return null;
    return file.readAsStringSync();
  }

  /// Returns the file handle, or `null` when the file does not exist.
  Future<File?> getFile({String? fileName, String? path}) async {
    final String resolved = await _resolvePath(fileName, path);
    final File file = File(resolved);
    return file.existsSync() ? file : null;
  }

  /// Deletes a file on disk.
  ///
  /// Returns `true` if the file did not exist or was successfully deleted,
  /// and `false` if the deletion failed.
  Future<bool> deleteFile({String? fileName, String? path}) async {
    final String resolved = await _resolvePath(fileName, path);
    final File file = File(resolved);
    if (!file.existsSync()) return true;
    try {
      file.deleteSync();
      return !file.existsSync();
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
    final Uint8List? bytes =
        await readFileAsBytes(fileName: imageName, path: path);
    if (bytes == null) return null;
    return Image.memory(bytes, fit: fit);
  }

  /// Loads a file whose name is stored in a column of an SQLite table.
  ///
  /// * [urlColumnName]: name of the column that holds the file name.
  /// * [key] / [value]: condition used to locate the row (`WHERE key = value`).
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
    final List<String> urls = await DataAccess.instance.getAColumnFrom<String, T>(
      urlColumnName,
      afterWhere: "$key = '$value' LIMIT 1",
    );
    if (urls.isEmpty) return null;
    final String fileRef = urls.first;

    final String? filePath =
        path != null ? '$path$pathJoin$fileRef' : null;

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

  /// Builds an absolute path from either an explicit [path] or a file name
  /// relative to [filesPath].
  Future<String> _resolvePath(String? fileName, String? path) async {
    final String? validated = validatePath(path);
    if (validated != null) return validated;
    return '${await filesPath}$pathJoin${fileName ?? ''}';
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
    final List<InternetAddress> result =
        await InternetAddress.lookup('google.com');
    return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
  } on SocketException {
    return false;
  }
}
