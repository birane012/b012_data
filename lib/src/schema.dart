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
  } on NoSuchMethodError {
    return null;
  } catch (e, s) {
    onError(name, e, s);
    return null;
  }
}

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

/// The `CREATE TABLE` statement of [entity] for [table], built from
/// `toMap()` and the optional getters `pKeyAuto`, `notNulls`, `uniques`,
/// `checks`, `defaults` and `fKeys` — the text 2.0.3 wrote, with names that
/// are SQL keywords (or not plain identifiers) quoted.
String buildCreateTable(
  Object entity,
  String table,
  GetterErrorHandler onGetterError,
) {
  final MapEntry<String, bool>? pKeyAuto = readGetter(
    entity,
    'pKeyAuto',
    (dynamic e) => e.pKeyAuto as MapEntry<String, bool>?,
    onGetterError,
  );
  final List<String>? notNulls = readGetter(
    entity,
    'notNulls',
    (dynamic e) => (e.notNulls as List<Object?>?)?.cast<String>(),
    onGetterError,
  );
  final List<String>? uniques = readGetter(
    entity,
    'uniques',
    (dynamic e) => (e.uniques as List<Object?>?)?.cast<String>(),
    onGetterError,
  );
  final Map<String, String>? checks = readGetter(
    entity,
    'checks',
    (dynamic e) => (e.checks as Map<Object?, Object?>?)?.cast<String, String>(),
    onGetterError,
  );
  final Map<String, String>? defaults = readGetter(
    entity,
    'defaults',
    (dynamic e) =>
        (e.defaults as Map<Object?, Object?>?)?.cast<String, String>(),
    onGetterError,
  );
  final Map<String, List<String>>? fKeys = readGetter(
    entity,
    'fKeys',
    (dynamic e) => (e.fKeys as Map<Object?, Object?>?)?.map(
      (Object? k, Object? v) =>
          MapEntry(k! as String, (v! as List<Object?>).cast<String>()),
    ),
    onGetterError,
  );

  // A copy: the entity may return a constant map.
  final Map<String, String> allChecks = <String, String>{...?checks};
  final Map<String, dynamic> objectMap =
      (entity as dynamic).toMap() as Map<String, dynamic>;
  final String lastFieldName = objectMap.keys.last;
  final bool hasForeignKey = fKeys != null && fKeys.isNotEmpty;

  final StringBuffer buffer = StringBuffer()
    ..write('CREATE TABLE ${quoteIdentifier(table)} (\n');
  objectMap.forEach((String columnName, dynamic columnValue) {
    final String dartType = dartTypeOf(columnValue as Object?);
    final String column = quoteIdentifier(columnName);
    if (dartType == 'bool') allChecks[columnName] = '$column IN (0, 1)';
    buffer.write('$column ${sqlTypeFor(dartType)}');
    if (pKeyAuto != null && pKeyAuto.key == columnName) {
      buffer.write(' PRIMARY KEY');
      if (pKeyAuto.value) buffer.write(' AUTOINCREMENT');
    }
    if (notNulls != null && notNulls.contains(columnName)) {
      buffer.write(' NOT NULL');
    }
    if (uniques != null && uniques.contains(columnName)) {
      buffer.write(' UNIQUE');
    }
    if (defaults != null && defaults.containsKey(columnName)) {
      buffer.write(' DEFAULT ${defaults[columnName]}');
    }
    if (allChecks.containsKey(columnName)) {
      buffer.write(' CHECK(${allChecks[columnName]})');
    }
    buffer.write(columnName != lastFieldName || hasForeignKey ? ',\n' : '\n)');
  });

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
