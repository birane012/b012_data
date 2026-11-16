// Checks the Flutter-free entry with the plain Dart VM (no Flutter):
//   dart run tool/dart_check/main.dart
// An encrypted database is created in a temporary folder, written, read
// again, and refused with a wrong key.
import 'dart:io';

import 'package:b012_data/b012_data_dart.dart';

Future<void> main() async {
  final Directory dir = await Directory.systemTemp.createTemp('b012_dart_');
  try {
    setDatabasesDirectory(dir.path);
    final DataAccess data = DataAccess.instance;
    await data.useEncryptionKey('essai');
    await data.rawExecute('CREATE TABLE note (texte TEXT)');
    await data.rawExecute('INSERT INTO note (texte) VALUES (?)', <Object?>['Texte témoin']);
    final List<Map<String, Object?>> rows = await data.rawQuery('SELECT texte FROM note');
    if (rows.single['texte'] != 'Texte témoin') throw StateError('read back: $rows');
    await data.closeDB();
    final String raw = String.fromCharCodes(File('${dir.path}/sqlf_easy.db').readAsBytesSync());
    if (raw.contains('Texte')) throw StateError('the file is not encrypted');
    await data.useEncryptionKey('autre');
    var refused = false;
    try {
      await data.rawQuery('SELECT texte FROM note');
    } catch (_) {
      refused = true;
    }
    if (!refused) throw StateError('a wrong key opened the database');
    await data.useEncryptionKey(null);
    stdout.writeln('OK: Flutter-free entry, encrypted database in ${dir.path}');
  } finally {
    await dir.delete(recursive: true);
  }
}
