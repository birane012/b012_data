import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:sqflite_common/sqlite_api.dart';

import 'package:b012_data/b012_disc_data.dart';

import 'src/backend.dart';
import 'src/column_type.dart';
import 'src/executor.dart';
import 'src/schema.dart';
import 'src/sql.dart';

export 'src/column_type.dart';

/// Receives every error that a method turns into `false`, `null` or `[]`
/// outside strict mode.
typedef B012ErrorHandler = void Function(Object error, StackTrace stack);

/// High-level API for persisting Dart objects into a local SQLite database.
///
/// [DataAccess] is a singleton: always access it through [DataAccess.instance].
/// It abstracts the differences between mobile platforms (Android, iOS, macOS),
/// which use the native `sqflite` plugin, and desktop platforms (Linux, Windows),
/// which use `sqflite_common_ffi`.
///
/// Entities exposed to this API are plain Dart classes that declare:
///   * A `toMap()` method returning a `Map<String, dynamic>`.
///   * A named constructor `fromMap(Map<String, Object?>)`.
///   * An instance method `fromMap(Map<String, Object?>)` used by generic getters.
///   * Optional getters: `pKeyAuto`, `notNulls`, `uniques`, `checks`, `defaults`, `fKeys`.
///
/// Filters passed as `afterWhere` text are inserted as is after `WHERE`:
/// never build them from user input. Put `?` placeholders in them and pass
/// the values in `whereArgs` instead.
///
/// See the package README for a complete usage example.
class DataAccess {
  DataAccess._internal();

  /// Global singleton instance.
  static final DataAccess instance = DataAccess._internal();

  final Backend _backend = createBackend();

  /// When `true`, methods that report a failure as `false`, `null` or `[]`
  /// throw the real error instead. "Nothing found" is still `null` or `[]`.
  /// Defaults to `false`, the 2.0.3 behaviour.
  bool strict = false;

  /// Receives every error turned into `false`, `null` or `[]` outside strict
  /// mode (the error is also printed with [debugPrint], as before).
  B012ErrorHandler? onError;

  Future<OpenedDatabase>? _opening;
  final Set<String> _knownTables = <String>{};
  Future<void> _tableLock = Future<void>.value();
  int _openCount = 0;

  /// Number of times the application database was opened (for tests).
  @visibleForTesting
  int get debugOpenCount => _openCount;

  void _report(String where, Object error, StackTrace stack) {
    debugPrint('$where failed: $error\n$stack');
    onError?.call(error, stack);
  }

  /// Runs [body]; outside strict mode an error is reported and [fallback]
  /// returned, as 2.0.3 did.
  Future<R> _guard<R>(
    String where,
    R fallback,
    Future<R> Function() body,
  ) async {
    try {
      return await body();
    } catch (e, s) {
      if (strict) rethrow;
      _report(where, e, s);
      return fallback;
    }
  }

  Future<OpenedDatabase> _open() {
    return _opening ??= _openApplicationDatabase().catchError((Object e) {
      _opening = null;
      throw e;
    });
  }

  Future<OpenedDatabase> _openApplicationDatabase({String? name}) async {
    final String dbName = name ?? await _currentDatabaseName();
    final OpenedDatabase opened = await _backend.open(dbName);
    _openCount++;
    return opened;
  }

  Future<String> _currentDatabaseName() async {
    final String directory = await DiscData.instance.databasesPath;
    final String dbFilePath = '$directory${DiscData.instance.pathJoin}dbName';
    return await DiscData.instance.readFileAsString(path: dbFilePath) ??
        'sqlf_easy.db';
  }

  Future<SqlExecutor> _executor() async => (await _open()).executor;

  String _tableOf(Object entity) => entity.runtimeType.toString();

  /// Opens (or returns the already opened) application database.
  ///
  /// The database name is read from a small text file stored at
  /// `<databasesPath>/dbName`. If the file does not exist, the default
  /// name `sqlf_easy.db` is used. The file is created/updated by [changeDB].
  /// Concurrent first calls share one opening.
  Future<Database> get db async {
    final Database? database = (await _open()).database;
    if (database == null) {
      throw UnsupportedError(
        'DataAccess.db is not available in a browser: use the DataAccess methods.',
      );
    }
    return database;
  }

  /// Opens a database located at [dbPath] and returns it.
  ///
  /// This does NOT replace the cached application database returned by [db].
  Future<Database> openDB(String dbPath) => _backend.openRaw(dbPath);

  /// Deletes the database file located at [dbPath].
  Future<void> dropDB(String dbPath) => _backend.delete(dbPath);

  /// Switches the application database to [newDBName].
  ///
  /// * If [newDBName] already exists it is opened and becomes the current
  ///   application database until the next call to [changeDB].
  /// * Otherwise it is created, opened and becomes the current database.
  ///
  /// The name (with the `.db` suffix appended if missing) is persisted to disk
  /// so that subsequent calls to [db] return the same database.
  Future<void> changeDB(String? newDBName) async {
    if (newDBName == null || newDBName.isEmpty) {
      debugPrint('changeDB called with a null or empty name.');
      return;
    }

    final String correctedName = newDBName.endsWith('.db')
        ? newDBName
        : '$newDBName.db';

    final String directory = await DiscData.instance.databasesPath;
    final String dbFilePath = '$directory${DiscData.instance.pathJoin}dbName';

    final String? saved = await DiscData.instance.saveDataToDisc(
      correctedName,
      DataType.text,
      path: dbFilePath,
    );
    if (saved == null) return;

    await closeDB();
    final Future<OpenedDatabase> opening = _openApplicationDatabase(
      name: correctedName,
    );
    _opening = opening;
    await opening;
    debugPrint('Database successfully changed to $correctedName');
  }

  /// Closes the current application database (if any).
  Future<void> closeDB() async {
    final Future<OpenedDatabase>? opening = _opening;
    _opening = null;
    _knownTables.clear();
    if (opening == null) return;
    try {
      await (await opening).close();
    } catch (_) {
      // An opening that failed has nothing to close.
    }
  }

  Map<String, dynamic> _rowOf(Object object) =>
      mapToUse((object as dynamic).toMap() as Map<String, dynamic>);

  Future<int> _insertRow(SqlExecutor executor, String table, Object object) {
    final Map<String, dynamic> row = _rowOf(object);
    final String columns = row.keys.map(quoteIdentifier).join(', ');
    final String marks = List<String>.filled(row.length, '?').join(', ');
    return executor.insert(
      'INSERT INTO ${quoteIdentifier(table)} ($columns) VALUES ($marks)',
      row.values.map(toSqlValue).toList(),
    );
  }

  /// Inserts [object] into its corresponding table.
  ///
  /// The table is created on first use if it does not exist yet.
  /// Returns `true` if exactly one row was inserted, `false` otherwise
  /// (null object, missing/renamed columns, constraint violation, ...).
  Future<bool> insertObjet(Object? object) async {
    if (object == null) return false;
    await createTableIfNotExists(object);
    return _guard('insertObjet', false, () async {
      final int rowId = await _insertRow(
        await _executor(),
        _tableOf(object),
        object,
      );
      return rowId > 0;
    });
  }

  /// Inserts a list of entity objects into their corresponding table.
  ///
  /// * All objects must be instances of the same entity class.
  /// * Returns `true` if every row was inserted successfully, `false` otherwise
  ///   (null/empty list, missing column, constraint violation, ...).
  /// * As in 2.0.3, rows inserted before a failing row are kept.
  Future<bool> insertObjetList(List<Object?>? objectlist) async {
    if (objectlist == null || objectlist.isEmpty) return false;
    final Object? first = objectlist.first;
    if (first == null) return false;

    final String table = _tableOf(first);
    await createTableIfNotExists(first);

    final SqlExecutor executor = await _executor();
    return executor.transaction((SqlExecutor tx) async {
      for (final Object? object in objectlist) {
        if (object == null) continue;
        try {
          if (await _insertRow(tx, table, object) <= 0) return false;
        } catch (e, s) {
          if (strict) rethrow;
          _report('insertObjetList', e, s);
          return false;
        }
      }
      return true;
    });
  }

  /// Authenticates a user by matching [identifierColumnName]=[identifierValue]
  /// and [passwordColumnName]=[passwordValue] against the entity table [T].
  ///
  /// Returns the matching entity instance or `null` if no row matches.
  ///
  /// Throws [DatabaseException] if the entity table does not exist. Wrap the
  /// call in `try`/`catch` if you are not sure that the table was created.
  Future<T?> getLogin<T>(
    Object tableEntityInstance,
    String identifierColumnName,
    String identifierValue,
    String passwordColumnName,
    String passwordValue,
  ) async {
    final List<Map<String, Object?>> rows = await (await _executor()).select(
      'SELECT * FROM ${quoteIdentifier(T.toString())} '
      'WHERE ${columnRef(identifierColumnName)} = ? '
      'AND ${columnRef(passwordColumnName)} = ?',
      <Object?>[identifierValue, passwordValue],
    );
    if (rows.isEmpty) return null;
    return (tableEntityInstance as dynamic).fromMap(rows.first) as T;
  }

  Future<List<Map<String, Object?>>> _selectWhere(
    String columns,
    String from,
    String? afterWhere,
    List<Object?>? whereArgs,
  ) async => (await _executor()).select(
    'SELECT $columns FROM $from${whereClause(afterWhere)}',
    toSqlValues(whereArgs),
  );

  List<T> _entities<T>(Object prototype, List<Map<String, Object?>> rows) =>
      rows
          .map(
            (Map<String, Object?> row) =>
                (prototype as dynamic).fromMap(row) as T,
          )
          .toList();

  /// Returns a single entity of type [T] matching the [afterWhere] clause, or
  /// `null` when no row matches. `?` placeholders in [afterWhere] take their
  /// values from [whereArgs].
  ///
  /// Throws [DatabaseException] if the entity table does not exist.
  Future<T?> get<T>(
    Object tableEntityInstance,
    String afterWhere, [
    List<Object?>? whereArgs,
  ]) async {
    final List<Map<String, Object?>> rows = await _selectWhere(
      '*',
      quoteIdentifier(T.toString()),
      afterWhere,
      whereArgs,
    );
    if (rows.isEmpty) return null;
    return (tableEntityInstance as dynamic).fromMap(rows.first) as T;
  }

  /// Returns every object of type [T] currently stored, or `null` when the
  /// table is empty.
  ///
  /// Throws [DatabaseException] if the entity table does not exist.
  Future<List<T>?> getAll<T>(Object tableEntityInstance) async {
    final List<Map<String, Object?>> rows = await _selectWhere(
      '*',
      quoteIdentifier(T.toString()),
      null,
      null,
    );
    if (rows.isEmpty) return null;
    return _entities<T>(tableEntityInstance, rows);
  }

  /// Returns every object of type [T] matching [afterWhere], or `null` when
  /// no row matches. Sort by putting `ORDER BY` at the end of [afterWhere];
  /// `?` placeholders take their values from [whereArgs].
  ///
  /// Throws [DatabaseException] if the entity table does not exist.
  Future<List<T>?> getAllSorted<T>(
    Object tableEntityInstance,
    String afterWhere, [
    List<Object?>? whereArgs,
  ]) async {
    final List<Map<String, Object?>> rows = await _selectWhere(
      '*',
      quoteIdentifier(T.toString()),
      afterWhere,
      whereArgs,
    );
    if (rows.isEmpty) return null;
    return _entities<T>(tableEntityInstance, rows);
  }

  /// Returns every value of column [columnName] (typed as [C]) from the entity
  /// table [T], optionally filtered by [afterWhere] and [whereArgs].
  ///
  /// Returns an empty list on error (outside [strict] mode); the error is
  /// printed with [debugPrint] and passed to [onError].
  Future<List<C>> getAColumnFrom<C, T>(
    String columnName, {
    String? afterWhere,
    List<Object?>? whereArgs,
  }) => _guard('getAColumnFrom', <C>[], () async {
    final List<Map<String, Object?>> rows = await _selectWhere(
      columnRef(columnName),
      quoteIdentifier(T.toString()),
      afterWhere,
      whereArgs,
    );
    return rows
        .map((Map<String, Object?> row) => row[columnName] as C)
        .toList();
  });

  /// Like [getAColumnFrom] but accepts an arbitrary [table] name (or a join
  /// expression). Useful for querying non-entity tables such as
  /// `sqlite_master` or to run joined queries with table aliases.
  ///
  /// Example:
  /// ```dart
  /// final names = await DataAccess.instance
  ///     .getAColumnFromWithTableName<String>(
  ///       'c.name',
  ///       'Custom c, Profile p',
  ///       afterWhere: 'c.profile = p.id AND p.name = ?',
  ///       whereArgs: ['faithful'],
  ///     );
  /// ```
  Future<List<T>> getAColumnFromWithTableName<T>(
    String columnName,
    String table, {
    String? afterWhere,
    List<Object?>? whereArgs,
  }) => _guard('getAColumnFromWithTableName', <T>[], () async {
    final List<Map<String, Object?>> rows = await _selectWhere(
      columnRef(columnName),
      table,
      afterWhere,
      whereArgs,
    );
    return rows
        .map((Map<String, Object?> row) => row[columnName] as T)
        .toList();
  });

  /// Returns raw rows (as `List<Map<String, Object?>>`) for the columns
  /// [listDesColonne] of the entity table [T].
  ///
  /// Example:
  /// ```dart
  /// final rows = await DataAccess.instance.getSomeColumnsFrom<Person>(
  ///   'firstName, lastName',
  ///   afterWhere: 'id = ?',
  ///   whereArgs: [1],
  /// );
  /// ```
  ///
  /// Throws [DatabaseException] if the entity table does not exist.
  Future<List<Map<String, Object?>>> getSomeColumnsFrom<T>(
    String listDesColonne, {
    String? afterWhere,
    List<Object?>? whereArgs,
  }) => _selectWhere(
    listDesColonne,
    quoteIdentifier(T.toString()),
    afterWhere,
    whereArgs,
  );

  /// Like [getSomeColumnsFrom] but takes an arbitrary [table] name (or a join
  /// expression). Useful for non-entity tables or join queries.
  Future<List<Map<String, Object?>>> getSommeColumnsWithTableName(
    String listDesColonne,
    String table, {
    String? afterWhere,
    List<Object?>? whereArgs,
  }) => _selectWhere(listDesColonne, table, afterWhere, whereArgs);

  void _getterFailed(String getter, Object error, StackTrace stack) {
    if (strict) Error.throwWithStackTrace(error, stack);
    _report('Entity getter "$getter"', error, stack);
  }

  /// Creates the entity table for [entity] if it does not exist yet.
  /// Concurrent calls are serialized; a table already seen is not looked up
  /// again.
  Future<void> createTableIfNotExists(Object entity) async {
    final String table = _tableOf(entity);
    if (_knownTables.contains(table)) return;
    final Completer<void> done = Completer<void>();
    final Future<void> previous = _tableLock;
    _tableLock = done.future;
    try {
      await previous;
      if (_knownTables.contains(table)) return;
      if (!await checkIfTableExists(table)) {
        await (await _executor()).execute(showCreateTable(entity));
      }
      _knownTables.add(table);
    } finally {
      done.complete();
    }
  }

  /// Returns the `CREATE TABLE` statement generated for [entity] based on the
  /// getters (`pKeyAuto`, `notNulls`, `uniques`, `checks`, `defaults`, `fKeys`)
  /// and the types declared in `toMap()`.
  ///
  /// A getter that exists but fails is printed and passed to [onError] (and
  /// thrown in [strict] mode); the table is then built without it.
  String showCreateTable(Object entity) =>
      buildCreateTable(entity, _tableOf(entity), _getterFailed);

  /// Returns the list of column names of the entity table [T] as currently
  /// stored in SQLite. Useful to detect schema drift (columns added or
  /// removed on the Dart side).
  Future<List<String>> getEntityColumnsName<T>() async {
    final List<Map<String, Object?>> rows = await (await _executor()).select(
      'PRAGMA table_info(${quoteAlways(T.toString())})',
    );
    return rows
        .map((Map<String, Object?> row) => row['name']! as String)
        .toList();
  }

  /// Returns `true` if a table named [table] exists.
  Future<bool> checkIfTableExists(String table) async {
    final List<Map<String, Object?>> rows = await (await _executor()).select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name = ?",
      <Object?>[table],
    );
    return rows.isNotEmpty;
  }

  /// Returns `true` if the entity table [T] exists.
  Future<bool> checkIfEntityTableExists<T>() =>
      checkIfTableExists(T.toString());

  /// Drops the entity table [T] if it exists.
  Future<void> dropTable<T>() async {
    final String table = T.toString();
    _knownTables.remove(table);
    await (await _executor()).execute(
      'DROP TABLE IF EXISTS ${quoteIdentifier(table)}',
    );
  }

  /// Updates one or more columns of the entity [T].
  ///
  /// * [columnsToUpadate]: names of the columns to update, in the order they
  ///   appear at the start of [values].
  /// * [whereColumns]: names of the columns appearing in the WHERE clause,
  ///   in the order they appear at the end of [values].
  /// * [values]: values for [columnsToUpadate] followed by values for
  ///   [whereColumns].
  /// * [whereMcop]: operator used to join multiple WHERE conditions:
  ///   `'AND'` (default) or `'OR'`.
  ///
  /// Example:
  /// ```dart
  /// final ok = await DataAccess.instance.updateSomeColumnsOf<Person>(
  ///   ['salary', 'married', 'year'],
  ///   ['name'],
  ///   [9000000, true, 45, 'Alpha'],
  /// );
  /// ```
  Future<bool> updateSomeColumnsOf<T>(
    List<String> columnsToUpadate,
    List<String> whereColumns,
    List<Object> values, {
    String whereMcop = 'AND',
  }) => _guard('updateSomeColumnsOf', false, () async {
    final String op = joinOperator(whereMcop);
    final int affected = await (await _executor()).change(
      'UPDATE ${quoteIdentifier(T.toString())} '
      'SET ${preparedColumns(columnsToUpadate, ',')} '
      'WHERE ${preparedColumns(whereColumns, op)}',
      toSqlValues(values),
    );
    return affected > 0;
  });

  /// Updates every column of an entity instance except the primary key.
  ///
  /// Example:
  /// ```dart
  /// final ok = await DataAccess.instance.updateWholeObject(
  ///   Person(18, 'M2Sir'),
  ///   ['name'],
  ///   ['Alpha'],
  /// );
  /// ```
  Future<bool> updateWholeObject(
    Object newObject,
    List<String> whereColumns,
    List<Object> values, {
    String whereMcop = 'AND',
  }) => _guard('updateWholeObject', false, () async {
    final String op = joinOperator(whereMcop);
    final Map<String, dynamic> row = _rowOf(newObject);
    final String sets = row.keys
        .map((String c) => '${quoteIdentifier(c)} = ?')
        .join(', ');
    final int affected = await (await _executor()).change(
      'UPDATE ${quoteIdentifier(_tableOf(newObject))} SET $sets '
      'WHERE ${preparedColumns(whereColumns, op)}',
      <Object?>[...row.values.map(toSqlValue), ...toSqlValues(values)],
    );
    return affected > 0;
  });

  /// Deletes every row of [T] matching [whereColumns] / [whereArgs].
  ///
  /// Example:
  /// ```dart
  /// final ok = await DataAccess.instance.delObjet<User>(
  ///   ['email', 'password'],
  ///   ['test@gmail.com', 'pass'],
  /// );
  /// ```
  ///
  /// Throws [DatabaseException] if the entity table does not exist, and
  /// [ArgumentError] if [whereMcop] is neither `'AND'` nor `'OR'`.
  Future<bool> delObjet<T>(
    List<String> whereColumns,
    List<Object> whereArgs, {
    String whereMcop = 'AND',
  }) async {
    final String op = joinOperator(whereMcop);
    final int affected = await (await _executor()).change(
      'DELETE FROM ${quoteIdentifier(T.toString())} '
      'WHERE ${preparedColumns(whereColumns, op)}',
      toSqlValues(whereArgs),
    );
    return affected > 0;
  }

  /// Deletes rows of [T] matching [afterWhere] (`?` placeholders take their
  /// values from [whereArgs]). When [afterWhere] is null **every row** of the
  /// table is removed (the table itself is preserved).
  ///
  /// Throws [DatabaseException] if the entity table does not exist.
  Future<bool> deleteObjet<T>([
    String? afterWhere,
    List<Object?>? whereArgs,
  ]) async {
    final int affected = await (await _executor()).change(
      'DELETE FROM ${quoteIdentifier(T.toString())}${whereClause(afterWhere)}',
      toSqlValues(whereArgs),
    );
    return affected > 0;
  }

  /// Counts rows of [T], optionally filtered by [afterWhere] and [whereArgs].
  ///
  /// * [expression]: expression passed to `COUNT(...)`; defaults to `'*'`.
  ///   Use `'DISTINCT column'` to count distinct values of a column.
  ///
  /// Throws [DatabaseException] if the entity table does not exist.
  Future<int> countElementsOf<T>({
    String expression = '*',
    String? afterWhere,
    List<Object?>? whereArgs,
  }) async {
    final List<Map<String, Object?>> rows = await _selectWhere(
      'count($expression) AS countElement',
      quoteIdentifier(T.toString()),
      afterWhere,
      whereArgs,
    );
    return (rows.first['countElement'] as int?) ?? 0;
  }

  /// Removes every row from every user-defined table of the database.
  /// The tables themselves are kept.
  Future<void> cleanAllTablesData() async {
    final List<String> tables = await getAColumnFromWithTableName<String>(
      'name',
      'sqlite_master',
      afterWhere: "type='table' AND name NOT LIKE 'sqlite_%'",
    );
    final SqlExecutor executor = await _executor();
    await executor.transaction((SqlExecutor tx) async {
      for (final String table in tables) {
        await tx.execute('DELETE FROM ${quoteIdentifier(table)}');
      }
    });
  }
}

/// Converts an entity map into a map suitable for SQLite.
///
/// * Values still equal to a [ColumnType] enum are replaced with `null`
///   (so they can be stored as SQL NULL).
/// * When [forDB] is true (the default), `bool` values are coerced to `0`/`1`
///   and `DateTime` values to their string representation.
///
/// Pass `forDB: false` when you want a plain Dart map (e.g. to serialize to
/// JSON or display it in the UI).
Map<String, dynamic> mapToUse(
  Map<String, dynamic> objectMap, {
  bool forDB = true,
}) {
  return objectMap.map((String key, dynamic value) {
    if (value is ColumnType) return MapEntry(key, null);
    if (forDB && value is bool) return MapEntry(key, value ? 1 : 0);
    if (forDB && value is DateTime) return MapEntry(key, value.toString());
    return MapEntry(key, value);
  });
}

/// String helpers used in the example app.
extension B012StringHelpers on String {
  /// Inserts a space every three digits: `'1234567'` -> `'1 234 567'`.
  String get spacedNumbers => replaceAllMapped(
    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
    (Match m) => '${m[1]} ',
  );
}

/// Python-like `range`:
/// * `range(5)` -> `0, 1, 2, 3, 4`.
/// * `range(2, 5)` -> `2, 3, 4`.
/// * `range(5, 2)` -> `2, 3, 4` (bounds are swapped when reversed).
Iterable<int> range(int lenOrStart, [int? end]) {
  if (end == null) {
    return Iterable<int>.generate(lenOrStart, (int index) => index);
  }
  int start = lenOrStart;
  int stop = end;
  if (stop < start) {
    final int tmp = start;
    start = stop;
    stop = tmp;
  }
  final int length = stop - start;
  return Iterable<int>.generate(length, (int index) => start + index);
}

/// Returns a new random 32-character key (`[0-9a-zA-Z]`), generated with a
/// cryptographically secure random source. Suitable as a text primary key.
String get newKey {
  const String alphabet =
      '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
  final Random rng = Random.secure();
  final StringBuffer buffer = StringBuffer();
  for (int i = 0; i < 32; i++) {
    buffer.write(alphabet[rng.nextInt(alphabet.length)]);
  }
  return buffer.toString();
}

/// Converts a SQLite boolean (stored as `0`/`1`) back to a Dart `bool`.
///
/// * When [isInt] is `true` (the default), [intOrBool] is read as a number.
/// * When [isInt] is `false`, [intOrBool] is returned as a `bool`.
/// * `null` stays `null`.
dynamic boolean(dynamic intOrBool, {bool isInt = true}) {
  if (intOrBool == null) return null;
  if (isInt) return (intOrBool as num) > 0;
  return intOrBool as bool;
}

/// Parses a date stored by b012_data (or any ISO-8601 text). Returns `null`
/// for `null`, an empty string or an unparsable text.
DateTime? dateTime(String? dateString) {
  if (dateString == null || dateString.isEmpty) return null;
  return DateTime.tryParse(dateString);
}
