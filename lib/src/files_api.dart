import 'dart:io' show File;
import 'dart:typed_data';

/// Where `DiscData` keeps its files: the file system on native platforms,
/// IndexedDB in a browser.
///
/// A file is designated either by a [fileName] inside [filesPath] (a name
/// that would leave it throws an [ArgumentError]) or by an explicit [path].
abstract class FileStore {
  /// The path separator of the platform.
  String get separator;

  Future<String> get rootPath;

  Future<String> get databasesPath;

  Future<String> get filesPath;

  /// Forgets cached folders (tests).
  void reset();

  /// The bytes of the file, or `null` when it does not exist.
  Future<Uint8List?> read({String? fileName, String? path});

  Future<bool> exists({String? fileName, String? path});

  /// Writes [bytes] all at once. With an explicit [path] and `recursive`
  /// false, a missing parent folder throws, as in 2.0.3.
  Future<void> write(
    List<int> bytes, {
    String? fileName,
    String? path,
    bool recursive = false,
  });

  /// Appends [bytes] to an existing file; does nothing if it is missing.
  Future<void> append(List<int> bytes, {String? fileName, String? path});

  /// `true` when the file does not exist afterwards.
  Future<bool> delete({String? fileName, String? path});

  /// The `dart:io` file, or `null` (always `null` in a browser).
  Future<File?> file({String? fileName, String? path});

  Future<bool> internetAvailable();
}
