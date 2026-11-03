import 'dart:io';

import 'package:b012_data/b012_disc_data.dart';
import 'package:b012_data/b012_sqlflite_easy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/entities.dart';
import 'support/harness.dart';

final DataAccess da = DataAccess.instance;

/// Where 2.0.3 put a database on Windows and Linux (observed, plan 1).
String legacyBase(String name) => p.join(
  Directory.current.path,
  '.dart_tool',
  'sqflite_common_ffi',
  'databases',
  name,
);

/// Creates a 2.0.3-style database with one Account row.
Future<void> makeLegacyBase(String name) async {
  sqfliteFfiInit();
  final String path = legacyBase(name);
  Directory(p.dirname(path)).createSync(recursive: true);
  final Database db = await databaseFactoryFfi.openDatabase(path);
  await db.execute(da.showCreateTable(Account()));
  await db.insert('Account', <String, Object?>{
    'email': 'old@b.c',
    'password': 'x',
  });
  await db.close();
}

void main() {
  late Sandbox sandbox;
  setUp(() async {
    sandbox = await Sandbox.create();
    DiscData.instance.debugResetPaths();
  });
  tearDown(() async {
    await da.closeDB();
    await sandbox.dispose();
    DiscData.instance.debugResetPaths();
  });

  test('a new installation keeps its base in the support folder', () async {
    final String path = (await da.db).path;
    expect(p.dirname(path), sandbox.path(p.join('Support', 'databases')));
    expect(p.basename(path), 'sqlf_easy.db');
    expect(File(legacyBase('sqlf_easy.db')).existsSync(), isFalse);
    expect(
      await DiscData.instance.databasesPath,
      sandbox.path(p.join('Support', 'databases')),
    );
  });

  test('the current directory no longer decides which base opens', () async {
    expect(await da.insertObjet(Account(null, 'a@b.c', 'x')), isTrue);
    await da.closeDB();
    final Directory elsewhere = Directory(sandbox.path('elsewhere'))
      ..createSync();
    Directory.current = elsewhere;
    expect(await da.countElementsOf<Account>(), 1);
  });

  test(
    'a 2.0.3 base under the current directory is adopted and kept',
    () async {
      await makeLegacyBase('sqlf_easy.db');
      expect(await da.getAColumnFrom<String, Account>('email'), <String>[
        'old@b.c',
      ]);
      expect((await da.db).path, legacyBase('sqlf_easy.db'));
      final File record = File(
        sandbox.path(p.join('Support', 'databases', 'locations.json')),
      );
      expect(record.existsSync(), isTrue);

      final String adopted = (await da.db).path;
      await da.closeDB();
      Directory.current = Directory(sandbox.path('Documents'));
      expect((await da.db).path, adopted);
      expect(await da.countElementsOf<Account>(), 1);
    },
  );

  test('the 2.0.3 pointer is followed when its base exists', () async {
    await makeLegacyBase('old.db');
    final Directory legacyPointerDir = Directory(sandbox.path('databases'))
      ..createSync();
    File(p.join(legacyPointerDir.path, 'dbName')).writeAsStringSync('old.db');
    expect((await da.db).path, legacyBase('old.db'));
    expect(await da.countElementsOf<Account>(), 1);
  });

  test('a 2.0.3 pointer without its base is ignored', () async {
    final Directory legacyPointerDir = Directory(sandbox.path('databases'))
      ..createSync();
    File(p.join(legacyPointerDir.path, 'dbName')).writeAsStringSync('gone.db');
    expect(p.basename((await da.db).path), 'sqlf_easy.db');
  });

  test('changeDB creates the folder it needs and remembers the name', () async {
    await da.changeDB('chantier');
    final String path = (await da.db).path;
    expect(path, sandbox.path(p.join('Support', 'databases', 'chantier.db')));
    expect(
      File(
        sandbox.path(p.join('Support', 'databases', 'dbName')),
      ).readAsStringSync(),
      'chantier.db',
    );
    await da.closeDB();
    expect((await da.db).path, path);
  });
}
