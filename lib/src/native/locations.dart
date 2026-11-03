import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'atomic_file.dart';

/// Where b012_data keeps its data on a native platform.
///
/// * Android, iOS, macOS: exactly as in 2.0.3 (the folders there already
///   belong to the application).
/// * Windows, Linux: a new installation uses the application support folder.
///   A base left by 2.0.3 under the current directory is adopted where it
///   is, and its absolute path is recorded so that the current directory no
///   longer matters.
class Locations {
  Locations._();

  static final Locations instance = Locations._();

  /// Windows and Linux, where 2.0.3 depended on the current directory.
  bool get isDesktop => Platform.isWindows || Platform.isLinux;

  String? _documents;
  String? _support;

  /// Forgets the cached folders (tests).
  void reset() {
    _documents = null;
    _support = null;
  }

  Future<String> get documentsDir async =>
      _documents ??= (await getApplicationDocumentsDirectory()).path;

  Future<String> get supportDir async =>
      _support ??= (await getApplicationSupportDirectory()).path;

  /// `<parent of Documents>/databases`, the 2.0.3 folder of `dbName`.
  Future<String> get legacyDatabasesDir async =>
      p.join(p.dirname(await documentsDir), 'databases');

  /// `<parent of Documents>/.files` (Windows) or `files`, the 2.0.3 folder of
  /// files saved by name.
  Future<String> get legacyFilesDir async => p.join(
    p.dirname(await documentsDir),
    Platform.isWindows ? '.files' : 'files',
  );

  /// The folder holding `dbName` (and, on Windows and Linux, the bases).
  Future<String> get databasesDir async => isDesktop
      ? p.join(await supportDir, 'databases')
      : await legacyDatabasesDir;

  /// Where 2.0.3 created the base [name] on Windows and Linux.
  String legacyDatabasePath(String name) => p.join(
    Directory.current.path,
    '.dart_tool',
    'sqflite_common_ffi',
    'databases',
    name,
  );

  Future<File> get _recordFile async =>
      File(p.join(await databasesDir, 'locations.json'));

  /// Bases adopted where 2.0.3 left them: name → absolute path.
  Future<Map<String, String>> readRecord() async {
    final File file = await _recordFile;
    if (!await file.exists()) return <String, String>{};
    final Object? decoded = jsonDecode(await file.readAsString());
    return decoded is Map
        ? decoded.map(
            (Object? k, Object? v) => MapEntry(k.toString(), v.toString()),
          )
        : <String, String>{};
  }

  Future<void> _writeRecord(Map<String, String> record) async =>
      writeAtomically(await _recordFile, utf8.encode(jsonEncode(record)));

  /// Whether this application adopted a 2.0.3 base on Windows or Linux: its
  /// files then stay in the 2.0.3 folder.
  Future<bool> get inheritedMode async =>
      isDesktop && (await readRecord()).isNotEmpty;

  /// The folder of files saved by name.
  Future<String> get filesDir async {
    if (!isDesktop || await inheritedMode) return legacyFilesDir;
    return p.join(await supportDir, 'files');
  }

  /// The 2.0.3 folder to look into when a file saved by name is not found
  /// (Windows and Linux, new installations only).
  Future<String?> get fallbackFilesDir async {
    if (!isDesktop || await inheritedMode) return null;
    return legacyFilesDir;
  }

  /// The name of the application database, as remembered by `changeDB`.
  Future<String?> readPointer() async {
    final File pointer = File(p.join(await databasesDir, 'dbName'));
    if (await pointer.exists()) return pointer.readAsString();
    if (!isDesktop) return null;
    // The 2.0.3 pointer sat in a folder shared by every application: follow
    // it only when this application has the base it names.
    final File legacy = File(p.join(await legacyDatabasesDir, 'dbName'));
    if (!await legacy.exists()) return null;
    final String name = await legacy.readAsString();
    return await File(legacyDatabasePath(name)).exists() ? name : null;
  }

  /// Remembers [name] as the application database.
  Future<void> writePointer(String name) async => writeAtomically(
    File(p.join(await databasesDir, 'dbName')),
    utf8.encode(name),
  );

  /// The path to open for the application database [name].
  Future<String> resolveDatabase(String name) async {
    if (!isDesktop) return name;
    final Map<String, String> record = await readRecord();
    final String? recorded = record[name];
    if (recorded != null) return recorded;
    final String legacy = legacyDatabasePath(name);
    if (await File(legacy).exists()) {
      record[name] = p.normalize(p.absolute(legacy));
      await _writeRecord(record);
      return record[name]!;
    }
    final Directory dir = Directory(await databasesDir);
    await dir.create(recursive: true);
    return p.join(dir.path, name);
  }
}
