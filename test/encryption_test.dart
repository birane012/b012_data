import 'dart:convert';
import 'dart:io';

import 'package:b012_data/b012_disc_data.dart';
import 'package:b012_data/b012_sqlflite_easy.dart';
import 'package:b012_data/src/crypto_files.dart';
import 'package:b012_data/src/encryption.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/entities.dart';
import 'support/harness.dart';

final DataAccess da = DataAccess.instance;
final DiscData disc = DiscData.instance;

bool fileContains(String path, String text) => latin1
    .decode(File(path).readAsBytesSync(), allowInvalid: true)
    .contains(text);

void main() {
  late Sandbox sandbox;
  setUp(() async {
    sandbox = await Sandbox.create();
    disc.debugResetPaths();
  });
  tearDown(() async {
    await da.useEncryptionKey(null);
    await da.closeDB();
    await sandbox.dispose();
    disc.debugResetPaths();
  });

  Future<String> basePath() async => (await da.db).path;

  test('a key encrypts a new database; the right key reads it back', () async {
    await da.useEncryptionKey('clé-1');
    expect(await da.insertObjet(Account(null, 'secret@b.c', 'pw')), isTrue);
    final String path = await basePath();
    await da.closeDB();
    expect(fileContains(path, 'secret@b.c'), isFalse);
    expect(await da.getAColumnFrom<String, Account>('email'), <String>[
      'secret@b.c',
    ]);
  });

  test('a wrong key, or no key, cannot read an encrypted database', () async {
    await da.useEncryptionKey('clé-1');
    await da.insertObjet(Account(null, 'a@b.c', 'pw'));
    await da.useEncryptionKey('autre');
    await expectLater(da.countElementsOf<Account>(), throwsStateError);
    await da.useEncryptionKey(null);
    await expectLater(da.countElementsOf<Account>(), throwsA(anything));
  });

  test(
    'a key given for a plaintext database is refused, data untouched',
    () async {
      expect(await da.insertObjet(Account(null, 'clair@b.c', 'pw')), isTrue);
      final String path = await basePath();
      await da.useEncryptionKey('clé-1');
      await expectLater(
        da.countElementsOf<Account>(),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('encryptDatabase'),
          ),
        ),
      );
      await da.useEncryptionKey(null);
      expect(await da.countElementsOf<Account>(), 1);
      expect(fileContains(path, 'clair@b.c'), isTrue);
    },
  );

  test('encryptDatabase encrypts the base and its files in place', () async {
    expect(await da.insertObjet(Account(null, 'clair@b.c', 'pw')), isTrue);
    await disc.saveDataToDisc(
      'photo-claire',
      DataType.text,
      takeThisName: 'photo.txt',
    );
    final String path = await basePath();
    final String photo = p.join(await disc.filesPath, 'photo.txt');

    await da.encryptDatabase('clé-1');

    expect(fileContains(path, 'clair@b.c'), isFalse);
    expect(fileContains(photo, 'photo-claire'), isFalse);
    expect(isEncryptedFile(File(photo).readAsBytesSync()), isTrue);
    expect(await da.getAColumnFrom<String, Account>('email'), <String>[
      'clair@b.c',
    ]);
    expect(await disc.readFileAsString(fileName: 'photo.txt'), 'photo-claire');
    await da.closeDB();
    await da.useEncryptionKey(null);
    await expectLater(da.countElementsOf<Account>(), throwsA(anything));
  });

  test('changeEncryptionKey: the old key fails, files stay readable', () async {
    await da.useEncryptionKey('clé-1');
    await da.insertObjet(Account(null, 'a@b.c', 'pw'));
    await disc.saveDataToDisc('note', DataType.text, takeThisName: 'n.txt');
    await da.changeEncryptionKey('clé-2');
    expect(await disc.readFileAsString(fileName: 'n.txt'), 'note');
    await da.useEncryptionKey('clé-1');
    await expectLater(da.countElementsOf<Account>(), throwsStateError);
    await da.useEncryptionKey('clé-2');
    expect(await da.countElementsOf<Account>(), 1);
    expect(await disc.readFileAsString(fileName: 'n.txt'), 'note');
  });

  test('files: encrypted by name, plain at an explicit path, old plain '
      'files readable, kept across cleanAllTablesData', () async {
    final String old = p.join(await disc.filesPath, 'old.txt');
    Directory(p.dirname(old)).createSync(recursive: true);
    File(old).writeAsStringSync('ancien');
    await da.useEncryptionKey('clé-1');
    await disc.saveDataToDisc(
      'confidentiel',
      DataType.text,
      takeThisName: 'c.txt',
    );
    final String stored = p.join(await disc.filesPath, 'c.txt');
    expect(fileContains(stored, 'confidentiel'), isFalse);
    expect(await disc.readFileAsString(fileName: 'c.txt'), 'confidentiel');
    expect(await disc.readFileAsString(fileName: 'old.txt'), 'ancien');

    final String export = sandbox.path('export.txt');
    await disc.saveDataToDisc('exporté', DataType.text, path: export);
    expect(File(export).readAsStringSync(), 'exporté');

    await da.insertObjet(Account(null, 'a@b.c', 'pw'));
    await da.cleanAllTablesData();
    expect(await disc.readFileAsString(fileName: 'c.txt'), 'confidentiel');
  });

  test('an engine that does not encrypt is refused before any write', () {
    expect(
      () => requireEncryptingEngine(<Map<String, Object?>>[]),
      throwsStateError,
    );
    expect(
      () => requireEncryptingEngine(<Map<String, Object?>>[
        <String, Object?>{'cipher': 'chacha20'},
      ]),
      returnsNormally,
    );
  });

  test('file cipher round trip and tamper detection', () async {
    final List<int> key = List<int>.generate(32, (int i) => i);
    final List<int> sealed = await sealFile(utf8.encode('bonjour'), key);
    expect(isEncryptedFile(sealed), isTrue);
    expect(utf8.decode(await openFile(sealed, key)), 'bonjour');
    sealed[sealed.length - 1] ^= 1;
    await expectLater(openFile(sealed, key), throwsA(anything));
  });
}
