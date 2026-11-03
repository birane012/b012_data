import 'package:sqflite_common/sqlite_api.dart';

/// Runs SQL that is already built, with bound values. One implementation
/// per platform family: sqflite on native platforms, `package:sqlite3` in a
/// browser.
abstract class SqlExecutor {
  Future<List<Map<String, Object?>>> select(
    String sql, [
    List<Object?> args = const <Object?>[],
  ]);

  /// Runs an INSERT and returns the row id of the last inserted row.
  Future<int> insert(String sql, [List<Object?> args = const <Object?>[]]);

  /// Runs an UPDATE or a DELETE and returns the number of changed rows.
  Future<int> change(String sql, [List<Object?> args = const <Object?>[]]);

  Future<void> execute(String sql, [List<Object?> args = const <Object?>[]]);

  /// Runs [action] in a transaction: everything or nothing. Inside a
  /// transaction, [action] receives the same executor.
  Future<T> transaction<T>(Future<T> Function(SqlExecutor tx) action);
}

/// An open database, whatever the platform.
class OpenedDatabase {
  OpenedDatabase({
    required this.executor,
    required this.path,
    required this.close,
    this.database,
  });

  final SqlExecutor executor;

  /// The sqflite database on native platforms; `null` in a browser.
  final Database? database;

  final String path;

  final Future<void> Function() close;
}

/// Opens and deletes databases on one platform family.
abstract class Backend {
  /// Opens the application database named or located at [nameOrPath].
  Future<OpenedDatabase> open(String nameOrPath);

  /// Opens a separate sqflite database (`DataAccess.openDB`).
  Future<Database> openRaw(String path);

  /// Deletes the database file at [path].
  Future<void> delete(String path);

  /// The application database name remembered by `changeDB`, if any.
  Future<String?> readPointer();

  /// Remembers [name] as the application database.
  Future<void> writePointer(String name);
}
