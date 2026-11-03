import 'column_type.dart';
import 'sql.dart';

/// Called when an optional entity getter exists but fails.
typedef GetterErrorHandler =
    void Function(String getter, Object error, StackTrace stack);

/// Reads an optional entity getter. An absent getter gives `null` silently;
/// a getter that fails (or returns the wrong type) is reported to [onError]
/// and gives `null`.
T? readGetter<T>(
  Object entity,
  String name,
  T? Function(dynamic entity) read,
  GetterErrorHandler onError,
) {
  try {
    return read(entity);
  } on NoSuchMethodError catch (e, s) {
    // Absent getter: the error names it. In a browser, release builds
    // shorten member names in error messages, so any NoSuchMethodError
    // counts as absent there.
    if (_inBrowser || e.toString().contains("'$name'")) return null;
    onError(name, e, s);
    return null;
  } catch (e, s) {
    onError(name, e, s);
    return null;
  }
}

const bool _inBrowser = bool.fromEnvironment('dart.library.js_interop');

/// SQLite type of a Dart type name.
String sqlTypeFor(String dartType) {
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

/// Dart type name of a `toMap()` value: the value's type, the name of a
/// [ColumnType] sentinel, or `String` for `null`.
String dartTypeOf(Object? value) {
  if (value == null) return 'String';
  if (value is ColumnType) return value.name;
  return value.runtimeType.toString();
}

List<String>? _strings(Object? value) =>
    (value as List<Object?>?)?.cast<String>();

Map<String, String>? _stringMap(Object? value) =>
    (value as Map<Object?, Object?>?)?.cast<String, String>();

Map<String, List<String>>? _listMap(Object? value) =>
    (value as Map<Object?, Object?>?)?.map(
      (Object? k, Object? v) =>
          MapEntry(k! as String, (v! as List<Object?>).cast<String>()),
    );

/// What an entity declares about its table, read once.
class EntitySchema {
  EntitySchema(Object entity, GetterErrorHandler onError)
    : pKeyAuto = readGetter(
        entity,
        'pKeyAuto',
        (dynamic e) => e.pKeyAuto as MapEntry<String, bool>?,
        onError,
      ),
      pKeys = readGetter(
        entity,
        'pKeys',
        (dynamic e) => _strings(e.pKeys),
        onError,
      ),
      notNulls = readGetter(
        entity,
        'notNulls',
        (dynamic e) => _strings(e.notNulls),
        onError,
      ),
      uniques = readGetter(
        entity,
        'uniques',
        (dynamic e) => _strings(e.uniques),
        onError,
      ),
      checks = readGetter(
        entity,
        'checks',
        (dynamic e) => _stringMap(e.checks),
        onError,
      ),
      defaults = readGetter(
        entity,
        'defaults',
        (dynamic e) => _stringMap(e.defaults),
        onError,
      ),
      fKeys = readGetter(
        entity,
        'fKeys',
        (dynamic e) => _listMap(e.fKeys),
        onError,
      ),
      indexes = readGetter(
        entity,
        'indexes',
        (dynamic e) => _listMap(e.indexes),
        onError,
      ),
      uniqueIndexes = readGetter(
        entity,
        'uniqueIndexes',
        (dynamic e) => _listMap(e.uniqueIndexes),
        onError,
      ),
      columns = ((entity as dynamic).toMap() as Map<String, dynamic>).map(
        (String k, dynamic v) => MapEntry(k, dartTypeOf(v as Object?)),
      );

  final MapEntry<String, bool>? pKeyAuto;
  final List<String>? pKeys;
  final List<String>? notNulls;
  final List<String>? uniques;
  final Map<String, String>? checks;
  final Map<String, String>? defaults;
  final Map<String, List<String>>? fKeys;
  final Map<String, List<String>>? indexes;
  final Map<String, List<String>>? uniqueIndexes;

  /// Column name → Dart type name, in `toMap()` order.
  final Map<String, String> columns;

  /// The CHECK of [column]: the boolean check for a `bool` column (which
  /// replaces a declared one, as in 2.0.3), else the declared one.
  String? checkOf(String column) => columns[column] == 'bool'
      ? '${quoteIdentifier(column)} IN (0, 1)'
      : checks?[column];

  bool get hasCompositeKey =>
      pKeyAuto == null && pKeys != null && pKeys!.isNotEmpty;
}

/// The `CREATE TABLE` statement for [table] — the text 2.0.3 wrote, with
/// names that are SQL keywords (or not plain identifiers) quoted, and a
/// composite primary key when the entity declares `pKeys`.
String buildCreateTable(EntitySchema s, String table) {
  final String lastFieldName = s.columns.keys.last;
  final Map<String, List<String>>? fKeys = s.fKeys;
  final bool hasForeignKey = fKeys != null && fKeys.isNotEmpty;
  final bool hasConstraints = hasForeignKey || s.hasCompositeKey;

  final StringBuffer buffer = StringBuffer()
    ..write('CREATE TABLE ${quoteIdentifier(table)} (\n');
  for (final String columnName in s.columns.keys) {
    buffer.write(columnDefinition(s, columnName, forAlter: false));
    buffer.write(columnName != lastFieldName || hasConstraints ? ',\n' : '\n)');
  }
  if (s.hasCompositeKey) {
    buffer.write(
      'PRIMARY KEY (${s.pKeys!.map(quoteIdentifier).join(', ')})'
      '${hasForeignKey ? ',\n' : '\n)'}',
    );
  }
  if (hasForeignKey) {
    final String lastFKeyField = fKeys.keys.last;
    fKeys.forEach((String field, List<String> target) {
      buffer.write(
        'FOREIGN KEY(${quoteIdentifier(field)}) REFERENCES '
        '${quoteIdentifier(target.first)}(${quoteIdentifier(target[1])})'
        '${field != lastFKeyField ? ',\n' : '\n)'}',
      );
    });
  }
  return buffer.toString();
}

/// One column of [s]. For `ALTER TABLE ... ADD COLUMN` ([forAlter]), SQLite
/// refuses PRIMARY KEY and UNIQUE, and NOT NULL without a default.
String columnDefinition(
  EntitySchema s,
  String columnName, {
  required bool forAlter,
}) {
  final StringBuffer line = StringBuffer(
    '${quoteIdentifier(columnName)} ${sqlTypeFor(s.columns[columnName]!)}',
  );
  final MapEntry<String, bool>? pKeyAuto = s.pKeyAuto;
  if (!forAlter && pKeyAuto != null && pKeyAuto.key == columnName) {
    line.write(' PRIMARY KEY');
    if (pKeyAuto.value) line.write(' AUTOINCREMENT');
  }
  final String? defaultValue = s.defaults?[columnName];
  final bool notNull = s.notNulls?.contains(columnName) ?? false;
  if (notNull && (!forAlter || defaultValue != null)) line.write(' NOT NULL');
  if (!forAlter && (s.uniques?.contains(columnName) ?? false)) {
    line.write(' UNIQUE');
  }
  if (defaultValue != null) line.write(' DEFAULT $defaultValue');
  final String? check = s.checkOf(columnName);
  if (check != null) line.write(' CHECK($check)');
  return line.toString();
}

/// Every index name [s] declares.
Iterable<String> indexNames(EntitySchema s) => <String>[
  ...?s.indexes?.keys,
  ...?s.uniqueIndexes?.keys,
];

/// `CREATE [UNIQUE] INDEX IF NOT EXISTS` statements of [s] for [table].
List<String> buildIndexes(EntitySchema s, String table) => <String>[
  for (final MapEntry<String, List<String>> e
      in (s.indexes ?? const <String, List<String>>{}).entries)
    'CREATE INDEX IF NOT EXISTS ${quoteIdentifier(e.key)} '
        'ON ${quoteIdentifier(table)} (${e.value.map(quoteIdentifier).join(', ')})',
  for (final MapEntry<String, List<String>> e
      in (s.uniqueIndexes ?? const <String, List<String>>{}).entries)
    'CREATE UNIQUE INDEX IF NOT EXISTS ${quoteIdentifier(e.key)} '
        'ON ${quoteIdentifier(table)} (${e.value.map(quoteIdentifier).join(', ')})',
];
