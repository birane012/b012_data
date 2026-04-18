import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:b012_data/b012_disc_data.dart';

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
/// See the package README for a complete usage example.
class DataAccess {
  DataAccess._internal() {
    if (_needsFfi) {
      sqfliteFfiInit();
    }
  }

  /// Global singleton instance.
  static final DataAccess instance = DataAccess._internal();

  Database? _db;

  /// Whether the current platform needs the FFI backend (Linux / Windows).
  static bool get _needsFfi => Platform.isWindows || Platform.isLinux;

  /// Returns the correct [DatabaseFactory] for the current platform.
  DatabaseFactory get _factory =>
      _needsFfi ? databaseFactoryFfi : databaseFactory;

  /// Opens (or returns the already opened) application database.
  ///
  /// The database name is read from a small text file stored at
  /// `<databasesPath>/dbName`. If the file does not exist, the default
  /// name `sqlf_easy.db` is used. The file is created/updated by [changeDB].
  Future<Database> get db async {
    if (_db != null) return _db!;
    final String directory = await DiscData.instance.databasesPath;
    final String dbFilePath = '$directory${DiscData.instance.pathJoin}dbName';
    final String name =
        await DiscData.instance.readFileAsString(path: dbFilePath) ??
            'sqlf_easy.db';
    _db = await _factory.openDatabase(name);
    return _db!;
  }

  /// Opens a database located at [dbPath] and returns it.
  ///
  /// This does NOT replace the cached application database returned by [db].
  Future<Database> openDB(String dbPath) => _factory.openDatabase(dbPath);

  /// Deletes the database file located at [dbPath].
  Future<void> dropDB(String dbPath) => _factory.deleteDatabase(dbPath);

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

    final String correctedName =
        newDBName.endsWith('.db') ? newDBName : '$newDBName.db';

    final String directory = await DiscData.instance.databasesPath;
    final String dbFilePath = '$directory${DiscData.instance.pathJoin}dbName';

    final String? saved = await DiscData.instance
        .saveDataToDisc(correctedName, DataType.text, path: dbFilePath);
    if (saved == null) return;

    if (_db != null) {
      await _db!.close();
      _db = null;
    }
    _db = await _factory.openDatabase(correctedName);
    debugPrint('Database successfully changed to $correctedName');
  }

  /// Closes the current application database (if any).
  Future<void> closeDB() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
  }

  /// Inserts [object] into its corresponding table.
  ///
  /// The table is created on first use if it does not exist yet.
  /// Returns `true` if exactly one row was inserted, `false` otherwise
  /// (null object, missing/renamed columns, constraint violation, ...).
  Future<bool> insertObjet(Object? object) async {
    if (object == null) return false;
    await createTableIfNotExists(object);
    int rowId = 0;
    await (await db).transaction((txn) async {
      try {
        rowId = await txn.insert(
          object.runtimeType.toString(),
          mapToUse((object as dynamic).toMap() as Map<String, dynamic>),
        );
      } catch (e, s) {
        debugPrint('insertObjet failed: $e\n$s');
      }
    });
    return rowId > 0;
  }

  /// Inserts a list of entity objects into their corresponding table.
  ///
  /// * All objects must be instances of the same entity class.
  /// * Returns `true` if every row was inserted successfully, `false` otherwise
  ///   (null/empty list, missing column, constraint violation, ...).
  Future<bool> insertObjetList(List<Object?>? objectlist) async {
    if (objectlist == null || objectlist.isEmpty) return false;
    final Object? first = objectlist.first;
    if (first == null) return false;

    final String table = first.runtimeType.toString();
    await createTableIfNotExists(first);

    bool allInserted = true;
    await (await db).transaction((txn) async {
      for (final Object? object in objectlist) {
        if (object == null) continue;
        try {
          final int rowId = await txn.insert(
            table,
            mapToUse((object as dynamic).toMap() as Map<String, dynamic>),
          );
          if (rowId <= 0) {
            allInserted = false;
            break;
          }
        } catch (e, s) {
          debugPrint('insertObjetList failed: $e\n$s');
          allInserted = false;
          break;
        }
      }
    });
    return allInserted;
  }

  /// Replaces `true`/`false` / ISO dates in the WHERE clause with SQLite-safe
  /// literals (`1`/`0`, quoted strings).
  String _sanitizeWhere(String where) => where
      .replaceAll(RegExp(r'=\s*true\b'), ' = 1')
      .replaceAll(RegExp(r'=\s*false\b'), ' = 0')
      .replaceAllMapped(
        RegExp(r'=\s*\d{4}(-\d{2}){2}([ :]\d{2}){3}[.]?\d{0,6}'),
        (Match m) => " = '${m.group(0)?.split('=').last.trim()}'",
      );

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
    final List<Map<String, Object?>> rows = await (await db).transaction(
      (txn) => txn.rawQuery(
        'SELECT * FROM ${T.toString()} '
        'WHERE $identifierColumnName = ? AND $passwordColumnName = ?',
        <String>[identifierValue, passwordValue],
      ),
    );
    if (rows.isEmpty) return null;
    return (tableEntityInstance as dynamic).fromMap(rows.first) as T;
  }

  /// Returns a single entity of type [T] matching the [afterWhere] clause, or
  /// `null` when no row matches.
  ///
  /// Throws [DatabaseException] if the entity table does not exist.
  Future<T?> get<T>(Object tableEntityInstance, String afterWhere) async {
    final List<Map<String, Object?>> rows = await (await db).transaction(
      (txn) => txn.rawQuery(
        'SELECT * FROM ${T.toString()} WHERE ${_sanitizeWhere(afterWhere)}',
      ),
    );
    if (rows.isEmpty) return null;
    return (tableEntityInstance as dynamic).fromMap(rows.first) as T;
  }

  /// Returns every object of type [T] currently stored, or `null` when the
  /// table is empty.
  ///
  /// Throws [DatabaseException] if the entity table does not exist.
  Future<List<T>?> getAll<T>(Object tableEntityInstance) async {
    final List<Map<String, Object?>> rows = await (await db)
        .transaction((txn) => txn.query(T.toString()));
    if (rows.isEmpty) return null;
    return rows
        .map((Map<String, Object?> row) =>
            (tableEntityInstance as dynamic).fromMap(row) as T)
        .toList();
  }

  /// Returns every object of type [T] matching [afterWhere], or `null` when
  /// no row matches.
  ///
  /// Throws [DatabaseException] if the entity table does not exist.
  Future<List<T>?> getAllSorted<T>(
    Object tableEntityInstance,
    String afterWhere,
  ) async {
    final List<Map<String, Object?>> rows = await (await db).transaction(
      (txn) => txn.rawQuery(
        'SELECT * FROM ${T.toString()} WHERE ${_sanitizeWhere(afterWhere)}',
      ),
    );
    if (rows.isEmpty) return null;
    return rows
        .map((Map<String, Object?> row) =>
            (tableEntityInstance as dynamic).fromMap(row) as T)
        .toList();
  }

  /// Returns every value of column [columnName] (typed as [C]) from the entity
  /// table [T], optionally filtered by [afterWhere].
  ///
  /// Returns an empty list on error; the underlying error is logged with
  /// [debugPrint] to help debugging.
  Future<List<C>> getAColumnFrom<C, T>(
    String columnName, {
    String? afterWhere,
  }) async {
    try {
      final List<Map<String, Object?>> rows =
          await getSommeColumnsFrom<T>(columnName, afterWhere: afterWhere);
      return rows.map((Map<String, Object?> row) => row[columnName] as C).toList();
    } catch (e, s) {
      debugPrint('getAColumnFrom failed: $e\n$s');
      return <C>[];
    }
  }

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
  ///       afterWhere: "c.profile = p.id AND p.name = 'faithful'",
  ///     );
  /// ```
  Future<List<T>> getAColumnFromWithTableName<T>(
    String columnName,
    String table, {
    String? afterWhere,
  }) async {
    try {
      final List<Map<String, Object?>> rows = await getSommeColumnsWithTableName(
        columnName,
        table,
        afterWhere: afterWhere,
      );
      return rows.map((Map<String, Object?> row) => row[columnName] as T).toList();
    } catch (e, s) {
      debugPrint('getAColumnFromWithTableName failed: $e\n$s');
      return <T>[];
    }
  }

  /// Returns raw rows (as `List<Map<String, Object?>>`) for the columns
  /// [listDesColonne] of the entity table [T].
  ///
  /// Example:
  /// ```dart
  /// final rows = await DataAccess.instance
  ///     .getSommeColumnsFrom<Person>('firstName, lastName', afterWhere: 'id=1');
  /// ```
  ///
  /// Throws [DatabaseException] if the entity table does not exist.
  Future<List<Map<String, Object?>>> getSommeColumnsFrom<T>(
    String listDesColonne, {
    String? afterWhere,
  }) async {
    final String whereClause =
        afterWhere != null ? 'WHERE ${_sanitizeWhere(afterWhere)}' : '';
    return (await db).transaction(
      (txn) => txn.rawQuery(
        'SELECT $listDesColonne FROM ${T.toString()} $whereClause',
      ),
    );
  }

  /// Like [getSommeColumnsFrom] but takes an arbitrary [table] name (or a join
  /// expression). Useful for non-entity tables or join queries.
  Future<List<Map<String, Object?>>> getSommeColumnsWithTableName(
    String listDesColonne,
    String table, {
    String? afterWhere,
  }) async {
    final String whereClause =
        afterWhere != null ? 'WHERE ${_sanitizeWhere(afterWhere)}' : '';
    return (await db).transaction(
      (txn) => txn.rawQuery('SELECT $listDesColonne FROM $table $whereClause'),
    );
  }

  /// Creates the entity table for [entity] if it does not exist yet.
  Future<void> createTableIfNotExists(Object entity) async {
    final String tableName = entity.runtimeType.toString();
    if (await checkIfTableExists(tableName)) return;
    await (await db)
        .transaction((txn) => txn.execute(showCreateTable(entity)));
  }

  /// Returns the `CREATE TABLE` statement generated for [entity] based on the
  /// getters (`pKeyAuto`, `notNulls`, `uniques`, `checks`, `defaults`, `fKeys`)
  /// and the types declared in `toMap()`.
  String showCreateTable(Object entity) {
    final dynamic e = entity;

    MapEntry<String, bool>? pKeyAuto;
    List<String>? notNulls;
    List<String>? uniques;
    Map<String, String>? checks;
    Map<String, String>? defaults;
    Map<String, List<String>>? fKeys;

    try {
      pKeyAuto = e.pKeyAuto as MapEntry<String, bool>?;
    } catch (_) {}
    try {
      notNulls = (e.notNulls as List?)?.cast<String>();
    } catch (_) {}
    try {
      uniques = (e.uniques as List?)?.cast<String>();
    } catch (_) {}
    try {
      checks = (e.checks as Map?)?.cast<String, String>();
    } catch (_) {}
    try {
      defaults = (e.defaults as Map?)?.cast<String, String>();
    } catch (_) {}
    try {
      fKeys = (e.fKeys as Map?)?.cast<String, List<String>>();
    } catch (_) {}

    final StringBuffer buffer = StringBuffer();
    buffer.write('CREATE TABLE ${entity.runtimeType.toString()} (\n');
    final Map<String, dynamic> objectMap =
        e.toMap() as Map<String, dynamic>;
    final String lastFieldName = objectMap.keys.last;
    final bool hasForeignKey = fKeys != null && fKeys.isNotEmpty;

    objectMap.forEach((String columnName, dynamic columnValue) {
      // columnValue.runtimeType is one of String, int, double, bool, DateTime,
      // Uint8List. When the value is null, the entity's toMap() puts a
      // ColumnType enum instead, so we extract the name from the enum.
      // If nothing suitable is found, fall back to TEXT.
      String columnType;
      if (columnValue == null) {
        columnType = 'String';
      } else if (columnValue is ColumnType) {
        columnType = columnValue.toString().split('.').last;
      } else {
        columnType = columnValue.runtimeType.toString();
      }

      if (columnType == 'bool') {
        checks ??= <String, String>{};
        checks![columnName] = '$columnName IN (0, 1)';
      }

      buffer.write(_writeTableColumn(
        columnName,
        _sqlTypeFor(columnType),
        pKeyAuto,
        notNulls,
        uniques,
        checks,
        defaults,
        lastFieldName,
        hasForeignKey,
      ));
    });

    if (hasForeignKey) {
      final String lastFKeyField = fKeys.keys.last;
      fKeys.forEach((String field, List<String> target) {
        buffer.write(
          'FOREIGN KEY($field) REFERENCES ${target.first}(${target[1]})'
          '${field != lastFKeyField ? ',\n' : '\n)'}',
        );
      });
    }
    return buffer.toString();
  }

  String _sqlTypeFor(String dartType) {
    switch (dartType) {
      case 'String':
        return 'TEXT';
      case 'int':
      case 'bool':
        return 'INTEGER';
      case 'double':
        return 'REAL';
      case 'DateTime':
        return 'DATETIME';
      default:
        return 'BLOB';
    }
  }

  /// Returns the list of column names of the entity table [T] as currently
  /// stored in SQLite. Useful to detect schema drift (columns added or
  /// removed on the Dart side).
  Future<List<String>> getEntityColumnsName<T>() async {
    List<String> columns = <String>[];
    await (await db).transaction((txn) async {
      final List<Map<String, Object?>> res = await txn.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name='${T.toString()}'",
      );
      if (res.isEmpty) return;
      final String? createStatement = res.first['sql'] as String?;
      if (createStatement == null) return;
      final List<String> lines = createStatement.split('\n');
      if (lines.length <= 2) return;
      columns = lines
          .sublist(1, lines.length - 1)
          .map((String line) => line.trim().split(' ').first)
          .where((String token) => token != 'FOREIGN')
          .toList();
    });
    return columns;
  }

  String _writeTableColumn(
    String columnName,
    String columnType,
    MapEntry<String, bool>? pKeyAuto,
    List<String>? notNulls,
    List<String>? uniques,
    Map<String, String>? checks,
    Map<String, String>? defaults,
    String objectLastFieldName,
    bool hasForeignKey,
  ) {
    final StringBuffer line = StringBuffer();
    line.write('$columnName $columnType');

    if (pKeyAuto != null && pKeyAuto.key == columnName) {
      line.write(' PRIMARY KEY');
      if (pKeyAuto.value) line.write(' AUTOINCREMENT');
    }

    if (notNulls != null && notNulls.contains(columnName)) {
      line.write(' NOT NULL');
    }

    if (uniques != null && uniques.contains(columnName)) {
      line.write(' UNIQUE');
    }

    if (defaults != null && defaults.containsKey(columnName)) {
      line.write(' DEFAULT ${defaults[columnName]}');
    }

    if (checks != null && checks.containsKey(columnName)) {
      line.write(' CHECK(${checks[columnName]})');
    }

    line.write(
      columnName != objectLastFieldName || hasForeignKey ? ',\n' : '\n)',
    );
    return line.toString();
  }

  /// Returns `true` if a table named [table] exists.
  Future<bool> checkIfTableExists(String table) async {
    final List<Map<String, Object?>> rows = await (await db).transaction(
      (txn) => txn.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='$table'",
      ),
    );
    return rows.isNotEmpty;
  }

  /// Returns `true` if the entity table [T] exists.
  Future<bool> checkIfEntityTableExists<T>() =>
      checkIfTableExists(T.toString());

  /// Drops the entity table [T] if it exists.
  Future<void> dropTable<T>() async {
    await (await db).transaction(
      (txn) => txn.execute('DROP TABLE IF EXISTS ${T.toString()}'),
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
  /// * [whereMcop]: operator used to join multiple WHERE conditions.
  ///   Defaults to `'AND'`. Any SQL boolean operator works: `'OR'`, `'AND'`.
  ///
  /// Example:
  /// ```dart
  /// final ok = await DataAccess.instance.updateSommeColumnsOf<Person>(
  ///   ['salary', 'married', 'year'],
  ///   ['name'],
  ///   [9000000, true, 45, 'Alpha'],
  /// );
  /// ```
  Future<bool> updateSommeColumnsOf<T>(
    List<String> columnsToUpadate,
    List<String> whereColumns,
    List<Object> values, {
    String whereMcop = 'AND',
  }) async {
    int affected = 0;
    await (await db).transaction((txn) async {
      try {
        affected = await txn.rawUpdate(
          'UPDATE ${T.toString()} '
          'SET ${_preparedColumns(columnsToUpadate, ',')} '
          'WHERE ${_preparedColumns(whereColumns, whereMcop)}',
          _checkForBoolAndDateTime(values),
        );
      } catch (e, s) {
        debugPrint('updateSommeColumnsOf failed: $e\n$s');
      }
    });
    return affected > 0;
  }

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
  }) async {
    int affected = 0;
    await (await db).transaction((txn) async {
      try {
        affected = await txn.update(
          newObject.runtimeType.toString(),
          mapToUse((newObject as dynamic).toMap() as Map<String, dynamic>),
          where: _preparedColumns(whereColumns, whereMcop),
          whereArgs: _checkForBoolAndDateTime(values),
        );
      } catch (e, s) {
        debugPrint('updateWholeObject failed: $e\n$s');
      }
    });
    return affected > 0;
  }

  /// Converts SQLite-incompatible values in [values] to compatible ones:
  /// `bool` becomes `0` / `1`, `DateTime` becomes its ISO string form.
  List<Object> _checkForBoolAndDateTime(List<Object> values) => values
      .map((Object value) {
        if (value is bool) return value ? 1 : 0;
        if (value is DateTime) return value.toString();
        return value;
      })
      .toList();

  /// Builds a prepared parameter list of the form
  /// `col1 = ? AND col2 = ? ...` from a list of column names.
  String _preparedColumns(List<String> columns, String joinOperator) =>
      columns
          .map((String column) => '$column = ?')
          .join(' $joinOperator ');

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
  /// Throws [DatabaseException] if the entity table does not exist.
  Future<bool> delObjet<T>(
    List<String> whereColumns,
    List<Object> whereArgs, {
    String whereMcop = 'AND',
  }) async {
    final int affected = await (await db).transaction(
      (txn) => txn.delete(
        T.toString(),
        where: _preparedColumns(whereColumns, whereMcop),
        whereArgs: whereArgs,
      ),
    );
    return affected > 0;
  }

  /// Deletes rows of [T] matching [afterWhere]. When [afterWhere] is null
  /// **every row** of the table is removed (the table itself is preserved).
  ///
  /// Throws [DatabaseException] if the entity table does not exist.
  Future<bool> deleteObjet<T>([String? afterWhere]) async {
    final String whereClause =
        afterWhere != null ? 'WHERE ${_sanitizeWhere(afterWhere)}' : '';
    final int affected = await (await db).transaction(
      (txn) => txn.rawDelete('DELETE FROM ${T.toString()} $whereClause'),
    );
    return affected > 0;
  }

  /// Counts rows of [T], optionally filtered by [afterWhere].
  ///
  /// * [expression]: expression passed to `COUNT(...)`; defaults to `'*'`.
  ///   Use `'DISTINCT column'` to count distinct values of a column.
  ///
  /// Throws [DatabaseException] if the entity table does not exist.
  Future<int> countElementsOf<T>({
    String expression = '*',
    String? afterWhere,
  }) async {
    final String whereClause =
        afterWhere != null ? ' WHERE ${_sanitizeWhere(afterWhere)}' : '';
    final List<Map<String, Object?>> rows = await (await db).transaction(
      (txn) => txn.rawQuery(
        'SELECT count($expression) AS countElement '
        'FROM ${T.toString()}$whereClause',
      ),
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
    await (await db).transaction((txn) async {
      for (final String table in tables) {
        await txn.execute('DELETE FROM $table');
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

/// Convenient [String] helpers used by the package.
extension B012StringHelpers on String {
  /// Inserts a thin space every three digits in a numeric string.
  ///
  /// Example: `'1234567'.spacedNumbers` returns `'1 234 567'`.
  String get spacedNumbers => replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (Match m) => '${m[1]} ',
      );
}

/// Generates an integer sequence, similar to Python's `range`.
///
/// * `range(n)` returns `0 .. n-1`.
/// * `range(start, end)` returns `start .. end-1`. When `end < start`, the
///   bounds are automatically swapped so the result is never empty.
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

/// Returns a 32-character random key made of digits, lowercase and uppercase
/// Latin letters. Handy for generating string-typed primary keys.
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

/// Primitive Dart types known by [DataAccess.showCreateTable].
///
/// When a column value is `null` in an entity's `toMap()`, the entity uses
/// one of these constants to tell the package which SQL column type to
/// generate for that column.
// ignore: constant_identifier_names
enum ColumnType { int, double, String, bool, DateTime, Uint8List }

/// Normalizes a SQLite boolean value.
///
/// * When [isInt] is true, [intOrBool] is expected to be `0`/`1` and a
///   corresponding `bool` is returned.
/// * When [isInt] is false, [intOrBool] is returned as is.
/// * `null` is passed through.
dynamic boolean(dynamic intOrBool, {bool isInt = true}) {
  if (intOrBool == null) return null;
  if (isInt) return (intOrBool as num) > 0;
  return intOrBool as bool;
}

/// Parses a SQLite DATETIME string into a [DateTime].
/// Returns `null` when [dateString] is `null` or empty.
DateTime? dateTime(String? dateString) {
  if (dateString == null || dateString.isEmpty) return null;
  return DateTime.tryParse(dateString);
}
