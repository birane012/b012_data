// Checks b012_data inside a real application, on the platform it runs on
// (see README.md): the database engine of the platform for plain bases,
// SQLite3MultipleCiphers for encrypted ones, and the real folders.
import 'dart:convert';
import 'dart:io';

import 'package:b012_data/b012_disc_data.dart';
import 'package:b012_data/b012_sqlflite_easy.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

class Note {
  Note([this.id, this.text]);

  Note.fromMap(Map<String, Object?> m)
    : id = m['id'] as int?,
      text = m['text'] as String?;

  int? id;
  String? text;

  MapEntry<String, bool> get pKeyAuto =>
      const MapEntry<String, bool>('id', true);

  Map<String, dynamic> toMap() => <String, dynamic>{
    'id': id ?? ColumnType.int,
    'text': text ?? ColumnType.String,
  };

  Note fromMap(Map<String, Object?> m) => Note.fromMap(m);
}

final DataAccess da = DataAccess.instance;
final DiscData disc = DiscData.instance;

const String key = 'clé-du-téléphone';

bool fileContains(String path, String text) => latin1
    .decode(File(path).readAsBytesSync(), allowInvalid: true)
    .contains(text);

bool isPlainSqlite(String path) => listEquals(
  File(path).readAsBytesSync().take(16).toList(),
  latin1.encode('SQLite format 3\u0000'),
);

/// The folder of the default base: where 2.0.3 put it on Android, iOS and
/// macOS, the application support folder on Windows and Linux.
Future<String> expectedDatabasesDir() async {
  if (Platform.isWindows || Platform.isLinux) {
    return p.join((await getApplicationSupportDirectory()).path, 'databases');
  }
  return sqflite.getDatabasesPath();
}

/// A base of its own for each run, so that two runs never meet.
String freshName(String what) =>
    '${what}_${DateTime.now().microsecondsSinceEpoch}';

Future<void> dropCurrent() async {
  final String path = (await da.db).path;
  await da.closeDB();
  await da.dropDB(path);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    await da.useEncryptionKey(null);
    await da.closeDB();
  });

  tearDownAll(() async {
    // Leave the default base, empty, as the current one.
    await da.useEncryptionKey(null);
    await da.changeDB('sqlf_easy');
    await dropCurrent();
  });

  testWidgets('the default base opens where 2.0.3 put it, in plain text', (
    _,
  ) async {
    await dropCurrent();
    expect(await da.insertObjet(Note(null, 'PLAIN_MARK')), isTrue);
    final String path = (await da.db).path;
    expect(p.isAbsolute(path), isTrue, reason: path);
    expect(p.basename(path), 'sqlf_easy.db');
    expect(
      p.equals(p.dirname(path), await expectedDatabasesDir()),
      isTrue,
      reason: path,
    );
    await da.closeDB();
    expect(isPlainSqlite(path), isTrue);
    expect(fileContains(path, 'PLAIN_MARK'), isTrue);
    expect(await da.getAColumnFrom<String, Note>('text'), <String>[
      'PLAIN_MARK',
    ]);
    await expectLater(
      da.transaction(() async {
        await da.insertObjet(Note(null, 'ROLLED_BACK'));
        throw StateError('abandon');
      }),
      throwsStateError,
    );
    expect(await da.countElementsOf<Note>(), 1);
    await dropCurrent();
  });

  testWidgets('encryptDatabase encrypts in place; without its key the base '
      'is refused and left byte for byte intact', (_) async {
    await da.changeDB(freshName('in_place'));
    expect(await da.insertObjet(Note(null, 'SECRET_MARK_1')), isTrue);
    expect(await da.insertObjet(Note(null, 'SECRET_MARK_2')), isTrue);
    await disc.saveDataToDisc(
      'PHOTO_MARK',
      DataType.text,
      takeThisName: 'photo.txt',
    );
    final String path = (await da.db).path;
    final String photo = p.join(await disc.filesPath, 'photo.txt');
    await da.closeDB();
    expect(fileContains(path, 'SECRET_MARK_1'), isTrue);
    expect(fileContains(photo, 'PHOTO_MARK'), isTrue);

    await da.encryptDatabase(key);

    expect(isPlainSqlite(path), isFalse);
    expect(fileContains(path, 'SECRET_MARK'), isFalse);
    expect(fileContains(photo, 'PHOTO_MARK'), isFalse);
    expect(await da.countElementsOf<Note>(), 2);
    expect(await disc.readFileAsString(fileName: 'photo.txt'), 'PHOTO_MARK');

    await da.closeDB();
    final Uint8List before = File(path).readAsBytesSync();
    await da.useEncryptionKey(null);
    await expectLater(da.countElementsOf<Note>(), throwsStateError);
    expect(listEquals(File(path).readAsBytesSync(), before), isTrue);
    await da.useEncryptionKey('wrong key');
    await expectLater(da.countElementsOf<Note>(), throwsStateError);
    expect(listEquals(File(path).readAsBytesSync(), before), isTrue);

    await da.useEncryptionKey(key);
    expect(await da.countElementsOf<Note>(), 2);
    await expectLater(
      da.transaction(() async {
        await da.insertObjet(Note(null, 'ROLLED_BACK'));
        throw StateError('abandon');
      }),
      throwsStateError,
    );
    expect(await da.countElementsOf<Note>(), 2);
    await da.closeDB();
    expect(await da.getAColumnFrom<String, Note>('text'), <String>[
      'SECRET_MARK_1',
      'SECRET_MARK_2',
    ]);
    await disc.deleteFile(fileName: 'photo.txt');
    await dropCurrent();
  });

  testWidgets('a base created with a key is encrypted from its first byte', (
    _,
  ) async {
    await da.useEncryptionKey(key);
    await da.changeDB(freshName('born_encrypted'));
    expect(await da.insertObjet(Note(null, 'BORN_MARK')), isTrue);
    final String path = (await da.db).path;
    await da.closeDB();
    expect(isPlainSqlite(path), isFalse);
    expect(fileContains(path, 'BORN_MARK'), isFalse);
    expect(await da.getAColumnFrom<String, Note>('text'), <String>[
      'BORN_MARK',
    ]);
    await dropCurrent();
  });
}
