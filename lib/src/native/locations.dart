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
///   longer matters. The decision is taken once, before any file or database
///   access, and never changes afterwards.
class Locations {
  Locations._();

  static final Locations instance = Locations._();

  /// Windows and Linux, where 2.0.3 depended on the current directory.
  bool get isDesktop => Platform.isWindows || Platform.isLinux;

  String? _documents;
  String? _support;
  Future<void>? _decided;

  /// Forgets the cached folders and decision (tests).
  void reset() {
    _documents = null;
    _support = null;
    _decided = null;
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

  /// The folder b012_data owns for its own records: the `dbName` pointer,
  /// `locations.json`, the files manifest — and, on Windows and Linux, the
  /// databases of a new installation.
  Future<String> get ownDatabasesDir async => isDesktop
      ? p.join(await supportDir, 'databases')
      : await legacyDatabasesDir;

  /// `DiscData.databasesPath`: the 2.0.3 folder for an application that kept
  /// its 2.0.3 database, the own folder otherwise.
  Future<String> get databasesDir async =>
      await inheritedMode ? legacyDatabasesDir : ownDatabasesDir;

  /// Where 2.0.3 created the base [name] on Windows and Linux.
  String legacyDatabasePath(String name) => p.join(
    Directory.current.path,
    '.dart_tool',
    'sqflite_common_ffi',
    'databases',
    name,
  );

  Future<File> get _recordFile async =>
      File(p.join(await ownDatabasesDir, 'locations.json'));

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

  /// Takes the location decision once: the application database is
  /// resolved (adopted or not) before anything depends on it.
  Future<void> _decide() => _decided ??= () async {
    if (!isDesktop) return;
    await resolveDatabase(await readPointer() ?? 'sqlf_easy.db');
  }();

  /// Whether this application adopted a 2.0.3 base on Windows or Linux: its
  /// files then stay in the 2.0.3 folder.
  Future<bool> get inheritedMode async {
    if (!isDesktop) return false;
    await _decide();
    return (await readRecord()).isNotEmpty;
  }

  /// The folder of files saved by name.
  Future<String> get filesDir async {
    if (!isDesktop || await inheritedMode) return legacyFilesDir;
    return p.join(await supportDir, 'files');
  }

  /// The 2.0.3 folder where a file saved by name is looked for when it is
  /// not found — for reading only (Windows and Linux, new installations).
  Future<String?> get fallbackFilesDir async {
    if (!isDesktop || await inheritedMode) return null;
    return legacyFilesDir;
  }

  /// The name of the application database, as remembered by `changeDB`.
  Future<String?> readPointer() async {
    final File pointer = File(p.join(await ownDatabasesDir, 'dbName'));
    if (await pointer.exists()) return pointer.readAsString();
    if (!isDesktop) return null;
    // The 2.0.3 pointer sat in a folder shared by every application: follow
    // it only when this application has the base it names — and then
    // remember both, so that the next launch finds them from anywhere.
    final File legacy = File(p.join(await legacyDatabasesDir, 'dbName'));
    if (!await legacy.exists()) return null;
    final String name = await legacy.readAsString();
    if (!await File(legacyDatabasePath(name)).exists()) return null;
    await resolveDatabase(name);
    await writePointer(name);
    return name;
  }

  /// Remembers [name] as the application database.
  Future<void> writePointer(String name) async => writeAtomically(
    File(p.join(await ownDatabasesDir, 'dbName')),
    utf8.encode(name),
  );

  /// The path to open for the application database [name]: the recorded
  /// one; else the base this installation already has in its own folder;
  /// else a 2.0.3 base under the current directory, adopted and recorded;
  /// else a new base in the own folder.
  Future<String> resolveDatabase(String name) async {
    if (!isDesktop) return name;
    final Map<String, String> record = await readRecord();
    final String? recorded = record[name];
    if (recorded != null) return recorded;
    final Directory own = Directory(await ownDatabasesDir);
    final String ownPath = p.join(own.path, name);
    if (await File(ownPath).exists()) return ownPath;
    final String legacy = legacyDatabasePath(name);
    if (await File(legacy).exists()) {
      record[name] = p.normalize(p.absolute(legacy));
      await _writeRecord(record);
      return record[name]!;
    }
    await own.create(recursive: true);
    return ownPath;
  }
}
