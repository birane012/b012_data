// Behaviour of b012_data 2.0.3, pinned before any change. Every test here
// must keep passing in 2.1: a failure means a break for current users.
import 'dart:io';

import 'package:b012_data/b012_disc_data.dart';
import 'package:b012_data/b012_sqlflite_easy.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/entities.dart';
import 'support/harness.dart';

final DataAccess da = DataAccess.instance;

Person _person(String id, String first, String last, bool sex, int year) =>
    Person(id, first, last, sex, DateTime(year, 5, 17, 8, 30));

Future<void> _threePersons() async {
  expect(
    await da.insertObjetList(<Person>[
      _person('p1', 'Birane', 'KEBE', true, 2000),
      _person('p2', 'Aliou', 'Mbaye', true, 1999),
      _person('p3', 'Fatou', 'Cisse', false, 2001),
    ]),
    isTrue,
  );
}

void main() {
  useSandbox();

  group('insert', () {
    test('insertObjet stores the entity and the values round-trip', () async {
      expect(
        await da.insertObjet(_person('p1', 'Birane', 'KEBE', true, 2000)),
        isTrue,
      );
      final List<Person>? all = await da.getAll<Person>(Person());
      expect(all, hasLength(1));
      expect(all!.single.firstName, 'Birane');
      expect(all.single.sex, isTrue);
      expect(all.single.dateOfBirth, DateTime(2000, 5, 17, 8, 30));
    });

    test('insertObjet(null) is false', () async {
      expect(await da.insertObjet(null), isFalse);
    });

    test('insertObjet violating NOT NULL is false, not an exception', () async {
      expect(await da.insertObjet(Person('p1')), isFalse);
    });

    test('insertObjet violating UNIQUE is false', () async {
      expect(await da.insertObjet(Account(null, 'a@b.c', 'x')), isTrue);
      expect(await da.insertObjet(Account(null, 'a@b.c', 'y')), isFalse);
    });

    test(
      'insertObjetList inserts every row; empty or null list is false',
      () async {
        await _threePersons();
        expect(await da.countElementsOf<Person>(), 3);
        expect(await da.insertObjetList(<Person>[]), isFalse);
        expect(await da.insertObjetList(null), isFalse);
      },
    );

    test('insertObjetList stops and reports false on a failing row', () async {
      expect(
        await da.insertObjetList(<Person>[
          _person('p1', 'A', 'B', true, 2000),
          Person('p2'),
        ]),
        isFalse,
      );
    });
  });

  group('read', () {
    test('getAll is null on an empty existing table', () async {
      await da.createTableIfNotExists(Person());
      expect(await da.getAll<Person>(Person()), isNull);
    });

    test('get finds one entity or null', () async {
      await _threePersons();
      final Person? p = await da.get<Person>(Person(), "firstName = 'Fatou'");
      expect(p?.idPers, 'p3');
      expect(await da.get<Person>(Person(), "firstName = 'Nobody'"), isNull);
    });

    test('getAllSorted takes ORDER BY and LIMIT inside afterWhere', () async {
      await _threePersons();
      final List<Person>? two = await da.getAllSorted<Person>(
        Person(),
        '1 = 1 ORDER BY firstName DESC LIMIT 2',
      );
      expect(two!.map((Person p) => p.firstName), <String>['Fatou', 'Birane']);
    });

    test('"= true" and "= false" are rewritten to 1 and 0', () async {
      await _threePersons();
      final List<Person>? men = await da.getAllSorted<Person>(
        Person(),
        'sex = true',
      );
      expect(men, hasLength(2));
      final List<Person>? women = await da.getAllSorted<Person>(
        Person(),
        'sex = false',
      );
      expect(women!.single.firstName, 'Fatou');
    });

    test('getAllSorted is null when nothing matches', () async {
      await _threePersons();
      expect(await da.getAllSorted<Person>(Person(), "lastName = 'X'"), isNull);
    });

    test('getAColumnFrom returns a column, and [] on error', () async {
      await _threePersons();
      expect(
        await da.getAColumnFrom<String, Person>(
          'firstName',
          afterWhere: 'sex = false',
        ),
        <String>['Fatou'],
      );
      expect(await da.getAColumnFrom<String, Account>('email'), isEmpty);
    });

    test('getSomeColumnsFrom returns raw rows', () async {
      await _threePersons();
      final List<Map<String, Object?>> rows = await da
          .getSomeColumnsFrom<Person>(
            'firstName, lastName',
            afterWhere: 'sex = 0',
          );
      expect(rows, <Map<String, Object?>>[
        <String, Object?>{'firstName': 'Fatou', 'lastName': 'Cisse'},
      ]);
    });

    test('getAColumnFromWithTableName reads any table or join', () async {
      await _threePersons();
      final List<String> tables = await da.getAColumnFromWithTableName<String>(
        'name',
        'sqlite_master',
        afterWhere: "type = 'table'",
      );
      expect(tables, contains('Person'));
      final List<Map<String, Object?>> joined = await da
          .getSommeColumnsWithTableName(
            'a.firstName, b.firstName AS f',
            'Person a, Person b',
            afterWhere: "a.idPers = 'p1' AND b.idPers = 'p3'",
          );
      expect(joined.single['f'], 'Fatou');
    });

    test('countElementsOf counts with a filter and an expression', () async {
      await _threePersons();
      expect(await da.countElementsOf<Person>(), 3);
      expect(await da.countElementsOf<Person>(afterWhere: 'sex = true'), 2);
      expect(await da.countElementsOf<Person>(expression: 'DISTINCT sex'), 2);
    });

    test('getLogin matches identifier and password', () async {
      await da.insertObjet(Account(null, 'a@b.c', 'secret'));
      final Account? ok = await da.getLogin<Account>(
        Account(),
        'email',
        'a@b.c',
        'password',
        'secret',
      );
      expect(ok?.email, 'a@b.c');
      expect(
        await da.getLogin<Account>(
          Account(),
          'email',
          'a@b.c',
          'password',
          'wrong',
        ),
        isNull,
      );
    });
  });

  group('update and delete', () {
    test('updateSomeColumnsOf: true on a match, false otherwise', () async {
      await _threePersons();
      expect(
        await da.updateSomeColumnsOf<Person>(
          <String>['firstName', 'sex'],
          <String>['lastName'],
          <Object>['Bira', false, 'KEBE'],
        ),
        isTrue,
      );
      final Person? p = await da.get<Person>(Person(), "idPers = 'p1'");
      expect(p!.firstName, 'Bira');
      expect(p.sex, isFalse);
      expect(
        await da.updateSomeColumnsOf<Person>(
          <String>['firstName'],
          <String>['lastName'],
          <Object>['X', 'Y'],
        ),
        isFalse,
      );
      expect(
        await da.updateSomeColumnsOf<Person>(
          <String>['unknown'],
          <String>['lastName'],
          <Object>['X', 'KEBE'],
        ),
        isFalse,
      );
    });

    test('updateSomeColumnsOf joins conditions with whereMcop', () async {
      await _threePersons();
      expect(
        await da.updateSomeColumnsOf<Person>(
          <String>['lastName'],
          <String>['idPers', 'idPers'],
          <Object>['Z', 'p1', 'p2'],
          whereMcop: 'OR',
        ),
        isTrue,
      );
      expect(await da.countElementsOf<Person>(afterWhere: "lastName = 'Z'"), 2);
    });

    test('updateWholeObject replaces every column of matching rows', () async {
      await _threePersons();
      expect(
        await da.updateWholeObject(
          _person('p1', 'New', 'Name', false, 1990),
          <String>['idPers'],
          <Object>['p1'],
        ),
        isTrue,
      );
      final Person? p = await da.get<Person>(Person(), "idPers = 'p1'");
      expect(p!.lastName, 'Name');
      expect(p.dateOfBirth, DateTime(1990, 5, 17, 8, 30));
    });

    test('delObjet deletes matching rows', () async {
      await _threePersons();
      expect(
        await da.delObjet<Person>(<String>['firstName'], <Object>['Fatou']),
        isTrue,
      );
      expect(
        await da.delObjet<Person>(<String>['firstName'], <Object>['Fatou']),
        isFalse,
      );
    });

    test('deleteObjet with a filter, then without: the table stays', () async {
      await _threePersons();
      expect(await da.deleteObjet<Person>("firstName = 'Aliou'"), isTrue);
      expect(await da.countElementsOf<Person>(), 2);
      expect(await da.deleteObjet<Person>(), isTrue);
      expect(await da.countElementsOf<Person>(), 0);
      expect(await da.checkIfEntityTableExists<Person>(), isTrue);
    });

    test('cleanAllTablesData empties every table and keeps them', () async {
      await _threePersons();
      await da.insertObjet(Account(null, 'a@b.c', 'x'));
      await da.cleanAllTablesData();
      expect(await da.countElementsOf<Person>(), 0);
      expect(await da.countElementsOf<Account>(), 0);
      expect(await da.checkIfEntityTableExists<Account>(), isTrue);
    });
  });

  group('schema', () {
    test('showCreateTable writes the exact 2.0.3 statement', () {
      expect(
        da.showCreateTable(Person()),
        'CREATE TABLE Person (\n'
        'idPers TEXT PRIMARY KEY,\n'
        'firstName TEXT NOT NULL,\n'
        'lastName TEXT NOT NULL,\n'
        'sex INTEGER NOT NULL CHECK(sex IN (0, 1)),\n'
        'dateOfBirth DATETIME NOT NULL\n'
        ')',
      );
      expect(
        da.showCreateTable(Account()),
        'CREATE TABLE Account (\n'
        'id INTEGER PRIMARY KEY AUTOINCREMENT,\n'
        'email TEXT UNIQUE,\n'
        'password TEXT,\n'
        'credit REAL DEFAULT 0\n'
        ')',
      );
    });

    test('table helpers', () async {
      expect(await da.checkIfEntityTableExists<Person>(), isFalse);
      await da.createTableIfNotExists(Person());
      expect(await da.checkIfTableExists('Person'), isTrue);
      expect(await da.getEntityColumnsName<Person>(), <String>[
        'idPers',
        'firstName',
        'lastName',
        'sex',
        'dateOfBirth',
      ]);
      await da.dropTable<Person>();
      expect(await da.checkIfEntityTableExists<Person>(), isFalse);
    });
  });

  group('database switching', () {
    test(
      'changeDB switches the application database and remembers it',
      () async {
        await da.changeDB('other');
        final String path = (await da.db).path;
        expect(path, endsWith('other.db'));
        // Exception (2.1, spec §5.4): the name is remembered in the
        // application's own databases folder, no longer in a folder shared
        // by every application of the computer.
        final File pointer = File(
          '${await DiscData.instance.databasesPath}'
          '${Platform.pathSeparator}dbName',
        );
        try {
          expect(pointer.readAsStringSync(), 'other.db');
          await da.closeDB();
          expect((await da.db).path, path);
        } finally {
          await da.closeDB();
          await da.dropDB(path);
          if (pointer.existsSync()) pointer.deleteSync();
        }
      },
    );
  });

  group('helpers', () {
    test('mapToUse converts for SQLite, or not', () {
      final DateTime d = DateTime(2000, 1, 2);
      expect(
        mapToUse(<String, dynamic>{'b': true, 'd': d, 'n': ColumnType.int}),
        <String, dynamic>{'b': 1, 'd': d.toString(), 'n': null},
      );
      expect(
        mapToUse(<String, dynamic>{'b': true, 'd': d}, forDB: false),
        <String, dynamic>{'b': true, 'd': d},
      );
    });

    test('spacedNumbers, range, newKey, boolean, dateTime', () {
      expect('1234567'.spacedNumbers, '1 234 567');
      expect(range(3).toList(), <int>[0, 1, 2]);
      expect(range(5, 2).toList(), <int>[2, 3, 4]);
      expect(newKey, hasLength(32));
      expect(newKey, isNot(newKey));
      expect(boolean(1), isTrue);
      expect(boolean(0), isFalse);
      expect(boolean(true, isInt: false), isTrue);
      expect(boolean(null), isNull);
      expect(
        dateTime('2000-01-02 03:04:05.000'),
        DateTime(2000, 1, 2, 3, 4, 5),
      );
      expect(dateTime(''), isNull);
    });
  });
}
