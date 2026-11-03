// Regressions found by the final review of 2.1, pinned before their fixes.
import 'dart:io';

import 'package:b012_data/b012_disc_data.dart';
import 'package:b012_data/b012_sqlflite_easy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/entities.dart';
import 'support/harness.dart';

final DataAccess da = DataAccess.instance;
final DiscData disc = DiscData.instance;

String legacyBase(String name) => p.join(
  Directory.current.path,
  '.dart_tool',
  'sqflite_common_ffi',
  'databases',
  name,
);

Future<void> makeLegacyBase(String name) async {
  sqfliteFfiInit();
  final String path = legacyBase(name);
  Directory(p.dirname(path)).createSync(recursive: true);
  final Database db = await databaseFactoryFfi.openDatabase(path);
  await db.execute(da.showCreateTable(Account()));
  await db.insert('Account', <String, Object?>{'email': 'old@b.c'});
  await db.close();
}

void main() {
  late Sandbox sandbox;
  setUp(() async {
    sandbox = await Sandbox.create();
    disc.debugResetPaths();
  });
  tearDown(() async {
    await da.useEncryptionKey(null);
    da.strict = false;
    await da.closeDB();
    await sandbox.dispose();
    disc.debugResetPaths();
  });

  group('C4 file writes', () {
    test('concurrent saves of one name keep one whole content', () async {
      await Future.wait(<Future<String?>>[
        for (int i = 0; i < 12; i++)
          disc.saveDataToDisc(
            'contenu $i',
            DataType.text,
            takeThisName: 'x.txt',
          ),
      ]);
      final String? text = await disc.readFileAsString(fileName: 'x.txt');
      expect(text, matches(RegExp(r'^contenu \d+$')));
      final List<String> left = Directory(
        await disc.filesPath,
      ).listSync().map((FileSystemEntity e) => p.basename(e.path)).toList();
      expect(left, <String>['x.txt']);
    });

    test('concurrent appends to an encrypted file lose nothing', () async {
      await da.useEncryptionKey('k');
      await disc.saveDataToDisc('>', DataType.text, takeThisName: 'log.txt');
      await Future.wait(<Future<void>>[
        for (int i = 0; i < 10; i++)
          disc.appendDataToFile('$i', DataType.text, fileName: 'log.txt'),
      ]);
      final String text = (await disc.readFileAsString(fileName: 'log.txt'))!;
      expect(text.length, 11);
    });
  });

  group('C3 encryptDatabase', () {
    test('leaves alone the files b012_data did not save', () async {
      await da.insertObjet(Account(null, 'a@b.c', 'pw'));
      await disc.saveDataToDisc(
        'mien',
        DataType.text,
        takeThisName: 'mine.txt',
      );
      final String foreign = p.join(await disc.filesPath, 'plugin', 'prefs.db');
      Directory(p.dirname(foreign)).createSync(recursive: true);
      File(foreign).writeAsStringSync('appartient à un autre plugin');
      await da.encryptDatabase('k');
      expect(File(foreign).readAsStringSync(), 'appartient à un autre plugin');
      expect(await disc.readFileAsString(fileName: 'mine.txt'), 'mien');
      final List<int> stored = File(
        p.join(await disc.filesPath, 'mine.txt'),
      ).readAsBytesSync();
      expect(String.fromCharCodes(stored.take(8)), 'B012ENC1');
    });
  });

  group('I1 the files key', () {
    test('is not lost when the first transaction rolls back', () async {
      await da.useEncryptionKey('k');
      await expectLater(
        da.transaction(() async {
          await disc.saveDataToDisc('a', DataType.text, takeThisName: 'a.txt');
          throw StateError('abandon');
        }),
        throwsStateError,
      );
      await disc.saveDataToDisc('b', DataType.text, takeThisName: 'b.txt');
      // As after a restart: the key in memory is forgotten.
      await da.useEncryptionKey('k');
      expect(await disc.readFileAsString(fileName: 'b.txt'), 'b');
    });
  });

  group('I2 I3 the 2.0.3 location', () {
    test(
      'a base chosen with changeDB in 2.0.3 stays found from elsewhere',
      () async {
        await makeLegacyBase('old.db');
        Directory(sandbox.path('databases')).createSync();
        File(
          sandbox.path(p.join('databases', 'dbName')),
        ).writeAsStringSync('old.db');
        expect(await da.countElementsOf<Account>(), 1);
        await da.closeDB();
        Directory.current = Directory(sandbox.path('Documents'));
        expect(await da.countElementsOf<Account>(), 1);
      },
    );

    test(
      'a support base used first is not replaced by a later old base',
      () async {
        expect(await da.insertObjet(Account(null, 'new@b.c', 'pw')), isTrue);
        await da.closeDB();
        await makeLegacyBase('sqlf_easy.db');
        expect(await da.getAColumnFrom<String, Account>('email'), <String>[
          'new@b.c',
        ]);
      },
    );

    test('databasesPath keeps the 2.0.3 folder for an adopted base', () async {
      await makeLegacyBase('sqlf_easy.db');
      await da.countElementsOf<Account>();
      expect(await disc.databasesPath, sandbox.path('databases'));
    });
  });

  group('I4 the shared 2.0.3 files folder', () {
    test('is read, never deleted or appended through', () async {
      final String legacy = sandbox.path(
        Platform.isWindows ? '.files' : 'files',
      );
      Directory(legacy).createSync();
      final File other = File(p.join(legacy, 'avatar.png'))
        ..writeAsStringSync('autre application');
      expect(
        await disc.readFileAsString(fileName: 'avatar.png'),
        'autre application',
      );
      await disc.appendDataToFile('!', DataType.text, fileName: 'avatar.png');
      await disc.deleteFile(fileName: 'avatar.png');
      expect(other.readAsStringSync(), 'autre application');
    });
  });

  group('I5 I6 transactions', () {
    test(
      'a failing insert inside a transaction rolls everything back',
      () async {
        await da.insertObjet(Account(null, 'a@b.c', 'pw'));
        await expectLater(
          da.transaction(() async {
            await da.insertObjet(Account(null, 'b@b.c', 'pw'));
            await da.insertObjet(Account(null, 'a@b.c', 'dup'));
          }),
          throwsA(isA<DatabaseException>()),
        );
        expect(await da.countElementsOf<Account>(), 1);
      },
    );

    test(
      'work started in a transaction and finished after it still lands',
      () async {
        await da.createTableIfNotExists(Account());
        late Future<bool> late;
        await da.transaction(() async {
          late = Future<void>.delayed(
            const Duration(milliseconds: 100),
          ).then((_) => da.insertObjet(Account(null, 'late@b.c', 'pw')));
        });
        expect(await late, isTrue);
        expect(await da.countElementsOf<Account>(), 1);
      },
    );
  });

  group('continuity', () {
    test(
      'a table dropped with raw SQL is recreated by the next insert',
      () async {
        await da.insertObjet(Account(null, 'a@b.c', 'pw'));
        await (await da.db).execute('DROP TABLE Account');
        expect(await da.insertObjet(Account(null, 'b@b.c', 'pw')), isTrue);
      },
    );

    test('updates still throw when the database cannot open', () async {
      File(
        sandbox.path(p.join('Support', 'databases')),
      ).parent.createSync(recursive: true);
      await da.useEncryptionKey('k');
      await da.insertObjet(Account(null, 'a@b.c', 'pw'));
      await da.useEncryptionKey('wrong');
      await expectLater(
        da.updateSomeColumnsOf<Account>(
          <String>['password'],
          <String>['email'],
          <Object>['x', 'a@b.c'],
        ),
        throwsStateError,
      );
    });
  });
}
