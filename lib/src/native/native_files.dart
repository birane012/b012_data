import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../files_api.dart';
import 'atomic_file.dart';
import 'locations.dart';

/// [FileStore] over the file system.
class NativeFileStore implements FileStore {
  final Locations _locations = Locations.instance;

  @override
  final String separator = Platform.isWindows ? r'\' : '/';

  @override
  Future<String> get rootPath => _locations.documentsDir;

  @override
  Future<String> get databasesPath => _locations.databasesDir;

  @override
  Future<String> get filesPath => _locations.filesDir;

  @override
  void reset() => _locations.reset();

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
  /// [filesPath] — or, with [fallback], when it is not there, in the 2.0.3
  /// folder (for reading only).
  Future<File> _existing(
    String? fileName,
    String? path, {
    bool fallback = false,
  }) async {
    if (path != null) return File(path);
    final String name = fileName ?? '';
    final File primary = File(_inFolder(await filesPath, name));
    if (!fallback || name.isEmpty || await primary.exists()) return primary;
    final String? legacy = await _locations.fallbackFilesDir;
    if (legacy == null) return primary;
    final File old = File(_inFolder(legacy, name));
    return await old.exists() ? old : primary;
  }

  @override
  Future<Uint8List?> read({
    String? fileName,
    String? path,
    bool fallback = true,
  }) async {
    final File file = await _existing(fileName, path, fallback: fallback);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  @override
  Future<bool> exists({String? fileName, String? path}) async =>
      (await _existing(fileName, path, fallback: true)).exists();

  @override
  Future<void> write(
    List<int> bytes, {
    String? fileName,
    String? path,
    bool recursive = false,
  }) async {
    final File file;
    if (path != null) {
      file = File(path);
      if (!recursive && !await file.parent.exists()) {
        throw PathNotFoundException(
          path,
          const OSError('The parent directory does not exist'),
          'Cannot create file',
        );
      }
    } else {
      file = File(_inFolder(await filesPath, fileName ?? ''));
    }
    await writeAtomically(file, bytes);
  }

  @override
  Future<void> append(List<int> bytes, {String? fileName, String? path}) async {
    final File file = await _existing(fileName, path);
    if (!await file.exists()) return;
    await file.writeAsBytes(bytes, mode: FileMode.append, flush: true);
  }

  @override
  Future<bool> delete({String? fileName, String? path}) async {
    final File file = await _existing(fileName, path);
    if (!await file.exists()) return true;
    await file.delete();
    return !await file.exists();
  }

  @override
  Future<File?> file({String? fileName, String? path}) async {
    final File file = await _existing(fileName, path, fallback: true);
    return await file.exists() ? file : null;
  }

  @override
  Future<String> get manifestPath async =>
      p.join(await _locations.ownDatabasesDir, 'b012_files.json');

  @override
  Future<bool> internetAvailable() async {
    try {
      final List<InternetAddress> result = await InternetAddress.lookup(
        'google.com',
      );
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    }
  }
}

FileStore createFileStore() => NativeFileStore();
