import 'dart:async';

import 'package:b012_data/b012_sqlflite_easy.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/entities.dart';
import 'support/harness.dart';
import 'support/limit_entities.dart';

final DataAccess da = DataAccess.instance;

Person _p(String id, String first) =>
    Person(id, first, 'Name', true, DateTime(2000));

void main() {
  useSandbox();
  tearDown(() async {
    da.debugClearRegistry();
    da.autoAddColumns = false;
    da.enforceForeignKeys = false;
    da.migrations = <int, Future<void> Function()>{};
    await da.closeDB();
  });

  group('registerEntity', () {
    test('every method follows the registered table name', () async {
      da.registerEntity<Person>('people');
      expect(await da.insertObjet(_p('p1', 'A')), isTrue);
      expect(await da.checkIfTableExists('people'), isTrue);
      expect(await da.checkIfTableExists('Person'), isFalse);
      expect(await da.checkIfEntityTableExists<Person>(), isTrue);
      expect(await da.countElementsOf<Person>(), 1);
      expect(await da.getAColumnFrom<String, Person>('firstName'), <String>[
        'A',
      ]);
      expect((await da.getEntityColumnsName<Person>()).first, 'idPers');
      expect((await da.get<Person>(Person(), "idPers = 'p1'"))?.firstName, 'A');
      expect(da.showCreateTable(Person()), startsWith('CREATE TABLE people ('));
      expect(await da.deleteObjet<Person>(), isTrue);
      await da.dropTable<Person>();
      expect(await da.checkIfTableExists('people'), isFalse);
    });
  });

  group('transaction', () {
    test('everything or nothing', () async {
      await expectLater(
        da.transaction(() async {
          await da.insertObjet(_p('p1', 'A'));
          expect(await da.countElementsOf<Person>(), 1);
          throw StateError('abandon');
        }),
        throwsStateError,
      );
      expect(await da.checkIfEntityTableExists<Person>(), isFalse);
      expect(await da.insertObjet(_p('p2', 'B')), isTrue);
      final int n = await da.transaction(() async {
        await da.insertObjet(_p('p3', 'C'));
        await da.updateSomeColumnsOf<Person>(
          <String>['lastName'],
          <String>['idPers'],
          <Object>['X', 'p2'],
        );
        return da.countElementsOf<Person>();
      });
      expect(n, 2);
      expect(await da.countElementsOf<Person>(afterWhere: "lastName = 'X'"), 1);
    });

    test('a nested transaction joins the outer one', () async {
      await expectLater(
        da.transaction(() async {
          await da.insertObjet(_p('p1', 'A'));
          await da.transaction(() => da.insertObjet(_p('p2', 'B')));
          throw StateError('abandon');
        }),
        throwsStateError,
      );
      await da.createTableIfNotExists(Person());
      expect(await da.countElementsOf<Person>(), 0);
    });

    test('a write outside a running transaction does not block', () async {
      await da.createTableIfNotExists(Account());
      final Completer<void> release = Completer<void>();
      final Future<void> tx = da.transaction(() async {
        await da.insertObjet(_p('p1', 'A'));
        await release.future;
      });
      final Future<bool> outside = da.insertObjet(Account(null, 'a@b.c', 'x'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      release.complete();
      await tx;
      expect(await outside.timeout(const Duration(seconds: 5)), isTrue);
    });
  });

  group('orReplace', () {
    test('replaces the row with the same key', () async {
      expect(await da.insertObjet(_p('p1', 'A')), isTrue);
      expect(await da.insertObjet(_p('p1', 'B')), isFalse);
      expect(await da.insertObjet(_p('p1', 'B'), orReplace: true), isTrue);
      expect(await da.getAColumnFrom<String, Person>('firstName'), <String>[
        'B',
      ]);
      expect(
        await da.insertObjetList(<Person>[
          _p('p1', 'C'),
          _p('p2', 'D'),
        ], orReplace: true),
        isTrue,
      );
      expect(await da.countElementsOf<Person>(), 2);
    });
  });

  group('composite key and indexes', () {
    test('pKeys, indexes and uniqueIndexes', () async {
      expect(
        da.showCreateTable(Assignment()),
        contains('PRIMARY KEY (maintenanceId, technicianId)'),
      );
      expect(await da.insertObjet(Assignment('m1', 't1', 'elec')), isTrue);
      expect(await da.insertObjet(Assignment('m1', 't2', 'meca')), isTrue);
      expect(await da.insertObjet(Assignment('m1', 't1', 'plomb')), isFalse);
      expect(await da.insertObjet(Assignment('m1', 't3', 'elec')), isFalse);
      final List<String> indexes = await da.getAColumnFromWithTableName<String>(
        'name',
        'sqlite_master',
        afterWhere: "type = 'index' AND tbl_name = 'Assignment'",
      );
      expect(
        indexes,
        containsAll(<String>['assignment_trade', 'assignment_one_trade']),
      );
    });
  });

  group('schema evolution', () {
    test('new columns are added only on demand', () async {
      da.registerEntity<ContactV1>('contact');
      da.registerEntity<ContactV2>('contact');
      expect(await da.insertObjet(ContactV1(null, 'Awa')), isTrue);
      expect(
        await da.insertObjet(ContactV2(null, 'Moussa', '77', true)),
        isFalse,
      );

      da.autoAddColumns = true;
      await da.closeDB();
      expect(
        await da.insertObjet(ContactV2(null, 'Moussa', '77', false)),
        isTrue,
      );
      expect(await da.getEntityColumnsName<ContactV2>(), <String>[
        'id',
        'name',
        'phone',
        'active',
      ]);
      final List<ContactV2>? all = await da.getAll<ContactV2>(ContactV2());
      expect(all!.first.active, isTrue);
      expect(all.first.phone, isNull);
      expect(all.last.active, isFalse);
    });

    test('versioned migrations run once, in order, all or nothing', () async {
      final List<int> ran = <int>[];
      da.migrations = <int, Future<void> Function()>{
        2: () async {
          ran.add(2);
          await da.rawExecute('INSERT INTO log (step) VALUES (2)');
        },
        1: () async {
          ran.add(1);
          await da.rawExecute('CREATE TABLE log (step INTEGER)');
        },
      };
      await da.closeDB();
      expect(await da.rawQuery('PRAGMA user_version'), <Map<String, Object?>>[
        <String, Object?>{'user_version': 2},
      ]);
      expect(ran, <int>[1, 2]);
      await da.closeDB();
      await da.rawQuery('SELECT 1');
      expect(ran, <int>[1, 2]);

      da.migrations = <int, Future<void> Function()>{
        ...da.migrations,
        3: () async {
          await da.rawExecute('INSERT INTO log (step) VALUES (3)');
          throw StateError('step 3 fails');
        },
      };
      await da.closeDB();
      await expectLater(da.rawQuery('SELECT 1'), throwsStateError);
      da.migrations = <int, Future<void> Function()>{};
      expect(await da.rawQuery('SELECT step FROM log'), <Map<String, Object?>>[
        <String, Object?>{'step': 2},
      ]);
      expect(
        (await da.rawQuery('PRAGMA user_version')).single['user_version'],
        2,
      );
    });
  });

  group('queries', () {
    test('query with where, order, limit and offset', () async {
      await da.insertObjetList(<Person>[
        _p('p1', 'A'),
        _p('p2', 'B'),
        _p('p3', 'C'),
        _p('p4', 'D'),
      ]);
      final List<Person> page = await da.query<Person>(
        Person(),
        where: 'idPers <> ?',
        whereArgs: <Object?>['p2'],
        orderBy: 'firstName DESC',
        limit: 2,
        offset: 1,
      );
      expect(page.map((Person p) => p.firstName), <String>['C', 'A']);
      expect(
        await da.query<Person>(
          Person(),
          where: 'idPers = ?',
          whereArgs: <Object?>['zz'],
        ),
        isEmpty,
      );
      expect(() => da.query<Person>(Person(), limit: -1), throwsArgumentError);
    });

    test('rawQuery, rawQueryAs, rawExecute', () async {
      await da.insertObjetList(<Person>[_p('p1', 'A'), _p('p2', 'B')]);
      expect(
        await da.rawQuery(
          'SELECT firstName FROM Person WHERE idPers = ?',
          <Object?>['p2'],
        ),
        <Map<String, Object?>>[
          <String, Object?>{'firstName': 'B'},
        ],
      );
      final List<Person> people = await da.rawQueryAs<Person>(
        Person(),
        'SELECT * FROM Person ORDER BY firstName DESC',
      );
      expect(people.first.idPers, 'p2');
      expect(
        await da.rawExecute(
          'UPDATE Person SET lastName = ? WHERE sex = ?',
          <Object?>['Z', true],
        ),
        2,
      );
    });
  });

  group('foreign keys', () {
    test('applied only on demand', () async {
      await da.insertObjet(Parent(1));
      expect(await da.insertObjet(Child(null, 99)), isTrue);
      da.enforceForeignKeys = true;
      await da.closeDB();
      expect(await da.insertObjet(Child(null, 99)), isFalse);
      expect(await da.insertObjet(Child(null, 1)), isTrue);
    });
  });
}
