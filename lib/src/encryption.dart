import 'dart:typed_data';

/// The first 16 bytes of an unencrypted SQLite database.
const List<int> sqliteHeader = <int>[
  0x53, 0x51, 0x4c, 0x69, 0x74, 0x65, 0x20, 0x66, //
  0x6f, 0x72, 0x6d, 0x61, 0x74, 0x20, 0x33, 0x00, //
];

/// Whether [head] starts like an unencrypted SQLite database.
bool isPlainSqlite(List<int> head) {
  if (head.length < sqliteHeader.length) return false;
  for (int i = 0; i < sqliteHeader.length; i++) {
    if (head[i] != sqliteHeader[i]) return false;
  }
  return true;
}

/// The message when a database that is not plain SQLite is opened without
/// a key.
String keyNeeded(String path) =>
    'The database $path is encrypted (or is not an SQLite database): call '
    'DataAccess.instance.useEncryptionKey(key) first. It is never opened '
    'without its key, so that nothing can erase it.';

/// [key] as an SQL string literal.
String sqlLiteral(String key) => "'${key.replaceAll("'", "''")}'";

/// Throws unless `PRAGMA cipher` answered like SQLite3MultipleCiphers: a key
/// must never silently produce a plaintext database.
void requireEncryptingEngine(List<Map<String, Object?>> pragmaCipherRows) {
  final bool encrypts =
      pragmaCipherRows.isNotEmpty &&
      pragmaCipherRows.first.values.any(
        (Object? v) => v != null && v.toString().isNotEmpty,
      );
  if (!encrypts) {
    throw StateError(
      'An encryption key was given, but the SQLite engine does not encrypt. '
      'Add to the pubspec.yaml of the application:\n'
      'hooks:\n  user_defines:\n    sqlite3:\n      source: sqlite3mc',
    );
  }
}

/// Hooks between DataAccess and DiscData, so that neither exposes them.
class EncryptionHooks {
  EncryptionHooks._();

  /// Set by DataAccess: the key of the files when the database is
  /// encrypted, `null` otherwise.
  static Future<Uint8List?> Function()? fileKey;

  /// Set by DiscData: encrypts the plaintext files saved by name.
  static Future<void> Function()? encryptExistingFiles;
}
