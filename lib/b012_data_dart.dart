/// b012_data without Flutter: servers, command-line tools, plain Dart tests.
///
/// The same [DataAccess] API as `b012_sqlflite_easy.dart`, over
/// `sqflite_common_ffi` and the SQLite bundled by `package:sqlite3`
/// (SQLite3MultipleCiphers for encryption, as in a Flutter application: put
/// the same `hooks: user_defines: sqlite3: source: sqlite3mc` lines in the
/// application's `pubspec.yaml`). The databases are opened in the folder given
/// to [setDatabasesDirectory] (the current directory by default).
///
/// Files saved with `DiscData` need Flutter and are not part of this entry.
library;

export 'b012_sqlflite_easy.dart';
export 'src/dart/dart_locations.dart' show setDatabasesDirectory, databasesDirectory;
