import 'column_type.dart';

/// Every SQLite keyword (https://sqlite.org/lang_keywords.html).
const Set<String> sqliteKeywords = <String>{
  'ABORT', 'ACTION', 'ADD', 'AFTER', 'ALL', 'ALTER', 'ALWAYS', 'ANALYZE', //
  'AND', 'AS', 'ASC', 'ATTACH', 'AUTOINCREMENT', 'BEFORE', 'BEGIN', //
  'BETWEEN', 'BY', 'CASCADE', 'CASE', 'CAST', 'CHECK', 'COLLATE', 'COLUMN', //
  'COMMIT', 'CONFLICT', 'CONSTRAINT', 'CREATE', 'CROSS', 'CURRENT', //
  'CURRENT_DATE', 'CURRENT_TIME', 'CURRENT_TIMESTAMP', 'DATABASE', //
  'DEFAULT', 'DEFERRABLE', 'DEFERRED', 'DELETE', 'DESC', 'DETACH', //
  'DISTINCT', 'DO', 'DROP', 'EACH', 'ELSE', 'END', 'ESCAPE', 'EXCEPT', //
  'EXCLUDE', 'EXCLUSIVE', 'EXISTS', 'EXPLAIN', 'FAIL', 'FILTER', 'FIRST', //
  'FOLLOWING', 'FOR', 'FOREIGN', 'FROM', 'FULL', 'GENERATED', 'GLOB', //
  'GROUP', 'GROUPS', 'HAVING', 'IF', 'IGNORE', 'IMMEDIATE', 'IN', 'INDEX', //
  'INDEXED', 'INITIALLY', 'INNER', 'INSERT', 'INSTEAD', 'INTERSECT', //
  'INTO', 'IS', 'ISNULL', 'JOIN', 'KEY', 'LAST', 'LEFT', 'LIKE', 'LIMIT', //
  'MATCH', 'MATERIALIZED', 'NATURAL', 'NO', 'NOT', 'NOTHING', 'NOTNULL', //
  'NULL', 'NULLS', 'OF', 'OFFSET', 'ON', 'OR', 'ORDER', 'OTHERS', 'OUTER', //
  'OVER', 'PARTITION', 'PLAN', 'PRAGMA', 'PRECEDING', 'PRIMARY', 'QUERY', //
  'RAISE', 'RANGE', 'RECURSIVE', 'REFERENCES', 'REGEXP', 'REINDEX', //
  'RELEASE', 'RENAME', 'REPLACE', 'RESTRICT', 'RETURNING', 'RIGHT', //
  'ROLLBACK', 'ROW', 'ROWS', 'SAVEPOINT', 'SELECT', 'SET', 'TABLE', 'TEMP', //
  'TEMPORARY', 'THEN', 'TIES', 'TO', 'TRANSACTION', 'TRIGGER', 'UNBOUNDED', //
  'UNION', 'UNIQUE', 'UPDATE', 'USING', 'VACUUM', 'VALUES', 'VIEW', //
  'VIRTUAL', 'WHEN', 'WHERE', 'WINDOW', 'WITH', 'WITHOUT', //
};

final RegExp _simpleIdentifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

/// Whether [name] is a plain identifier (letters, digits, underscores).
bool isSimpleIdentifier(String name) => _simpleIdentifier.hasMatch(name);

/// Whether [name] is an SQLite keyword, whatever its case.
bool isKeyword(String name) => sqliteKeywords.contains(name.toUpperCase());

/// [name] between double quotes, inner double quotes doubled.
String quoteAlways(String name) => '"${name.replaceAll('"', '""')}"';

/// A table or column name the package writes itself: unchanged when it is a
/// plain identifier that is not a keyword (so the SQL stays exactly what 2.0.3
/// wrote), quoted otherwise.
String quoteIdentifier(String name) =>
    isSimpleIdentifier(name) && !isKeyword(name) ? name : quoteAlways(name);

/// A column name given by the caller: protected when it is a plain identifier
/// (a keyword such as `order` gets quoted), passed as is otherwise, because
/// 2.0.3 accepted expressions there.
String columnRef(String name) =>
    isSimpleIdentifier(name) ? quoteIdentifier(name) : name;

/// The value SQLite stores, written exactly as b012_data has always written
/// it: a `bool` as 1/0, a `DateTime` by `toString()`, a [ColumnType]
/// sentinel as `null`.
Object? toSqlValue(Object? value) {
  if (value is ColumnType) return null;
  if (value is bool) return value ? 1 : 0;
  if (value is DateTime) return value.toString();
  return value;
}

/// [toSqlValue] applied to each value; `null` gives an empty list.
List<Object?> toSqlValues(Iterable<Object?>? values) =>
    values == null ? const <Object?>[] : values.map(toSqlValue).toList();

/// The 2.0.3 rewriting of an `afterWhere` text: `= true` / `= false` become
/// `= 1` / `= 0`, and a bare date literal gets quoted.
String sanitizeWhere(String where) => where
    .replaceAll(RegExp(r'=\s*true\b'), ' = 1')
    .replaceAll(RegExp(r'=\s*false\b'), ' = 0')
    .replaceAllMapped(
      RegExp(r'=\s*\d{4}(-\d{2}){2}([ :]\d{2}){3}[.]?\d{0,6}'),
      (Match m) => " = '${m.group(0)?.split('=').last.trim()}'",
    );

/// ` WHERE <afterWhere>` (sanitized), or an empty string.
String whereClause(String? afterWhere) =>
    afterWhere == null ? '' : ' WHERE ${sanitizeWhere(afterWhere)}';

/// The operator joining several conditions: only `AND` and `OR`.
String joinOperator(String whereMcop) {
  final String op = whereMcop.trim().toUpperCase();
  if (op != 'AND' && op != 'OR') {
    throw ArgumentError.value(whereMcop, 'whereMcop', 'must be AND or OR');
  }
  return op;
}

/// `col1 = ? <op> col2 = ? ...`.
String preparedColumns(List<String> columns, String op) =>
    columns.map((String c) => '${columnRef(c)} = ?').join(' $op ');
