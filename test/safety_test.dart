import 'package:b012_data/b012_disc_data.dart';
import 'package:b012_data/b012_sqlflite_easy.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/entities.dart';
import 'support/harness.dart';
import 'support/more_entities.dart';

final DataAccess da = DataAccess.instance;

Future<void> _persons() async {
  expect(
    await da.insertObjetList(<Person>[
      Person('p1', 'Birane', 'KEBE', true, DateTime(2000, 5, 17, 8, 30)),
      Person('p2', 'Aliou', 'Mbaye', true, DateTime(1999, 1, 2)),
      Person('p3', 'Fatou', 'Cisse', false, DateTime(2001, 3, 4)),
    ]),
    isTrue,
  );
}

void main() {
  useSandbox();
  tearDown(() {
    da.strict = false;
    da.onError = null;
  });

  group('values the package writes itself are bound', () {
    test(
      'getEntityFileOnDisc finds a row whose key holds an apostrophe',
      () async {
        expect(await da.insertObjet(Doc('d1', "L'été", 'note.txt')), isTrue);
        await DiscData.instance.saveDataToDisc(
          'contenu',
          DataType.text,
          takeThisName: 'note.txt',
          recursive: true,
        );
        expect(
          await DiscData.instance.getEntityFileOnDisc<String, Doc>(
            'url',
            'title',
            "L'été",
          ),
          'contenu',
        );
      },
    );

    test(
      'checkIfTableExists cannot be turned into an always-true query',
      () async {
        await da.createTableIfNotExists(Person());
        expect(await da.checkIfTableExists("x' OR '1'='1"), isFalse);
        expect(await da.checkIfTableExists('Person'), isTrue);
      },
    );
  });

  group('SQL keywords as names', () {
    test('an entity named Order with columns group and order works', () async {
      expect(await da.insertObjet(Order(null, 'A', 2)), isTrue);
      expect(await da.insertObjet(Order(null, 'B', 1)), isTrue);
      final List<Order>? all = await da.getAll<Order>(Order());
      expect(all!.map((Order o) => o.group), <String>['A', 'B']);
      expect(
        await da.updateSomeColumnsOf<Order>(
          <String>['order'],
          <String>['group'],
          <Object>[9, 'A'],
        ),
        isTrue,
      );
      expect(
        await da.getAColumnFrom<int, Order>(
          'order',
          afterWhere: '"group" = \'A\'',
        ),
        <int>[9],
      );
      expect(await da.countElementsOf<Order>(), 2);
      expect(await da.getEntityColumnsName<Order>(), <String>[
        'id',
        'group',
        'order',
      ]);
      expect(
        await da.delObjet<Order>(<String>['group'], <Object>['B']),
        isTrue,
      );
    });
  });

  group('whereArgs', () {
    test('bound date and boolean match the stored values', () async {
      await _persons();
      final Person? p = await da.get<Person>(
        Person(),
        'dateOfBirth = ? AND sex = ?',
        <Object?>[DateTime(2000, 5, 17, 8, 30), true],
      );
      expect(p?.idPers, 'p1');
      final List<Person>? men = await da.getAllSorted<Person>(
        Person(),
        'sex = ? ORDER BY firstName',
        <Object?>[true],
      );
      expect(men!.map((Person p) => p.firstName), <String>['Aliou', 'Birane']);
    });

    test('a bound value is data, never SQL', () async {
      await _persons();
      expect(
        await da.get<Person>(Person(), 'firstName = ?', <Object?>[
          "x' OR '1'='1",
        ]),
        isNull,
      );
      expect(
        await da.countElementsOf<Person>(
          afterWhere: 'lastName = ?',
          whereArgs: <Object?>["KEBE' OR 1=1 --"],
        ),
        0,
      );
    });

    test('every afterWhere method accepts whereArgs', () async {
      await _persons();
      expect(
        await da.getAColumnFrom<String, Person>(
          'firstName',
          afterWhere: 'sex = ?',
          whereArgs: <Object?>[false],
        ),
        <String>['Fatou'],
      );
      expect(
        await da.getSomeColumnsFrom<Person>(
          'lastName',
          afterWhere: 'idPers = ?',
          whereArgs: <Object?>['p1'],
        ),
        <Map<String, Object?>>[
          <String, Object?>{'lastName': 'KEBE'},
        ],
      );
      expect(
        await da.getAColumnFromWithTableName<String>(
          'lastName',
          'Person',
          afterWhere: 'idPers = ?',
          whereArgs: <Object?>['p2'],
        ),
        <String>['Mbaye'],
      );
      expect(
        await da.getSommeColumnsWithTableName(
          'count(*) AS n',
          'Person',
          afterWhere: 'sex = ?',
          whereArgs: <Object?>[true],
        ),
        <Map<String, Object?>>[
          <String, Object?>{'n': 2},
        ],
      );
      expect(
        await da.deleteObjet<Person>('idPers = ?', <Object?>['p2']),
        isTrue,
      );
      expect(
        await da.countElementsOf<Person>(
          afterWhere: 'sex = ?',
          whereArgs: <Object?>[true],
        ),
        1,
      );
    });
  });

  group('whereMcop', () {
    test('only AND and OR are accepted', () async {
      await _persons();
      final List<Object> errors = <Object>[];
      da.onError = (Object e, StackTrace s) => errors.add(e);
      expect(
        await da.updateSomeColumnsOf<Person>(
          <String>['lastName'],
          <String>['idPers', 'idPers'],
          <Object>['Z', 'p1', 'p2'],
          whereMcop: '; DROP TABLE Person; --',
        ),
        isFalse,
      );
      expect(errors.single, isA<ArgumentError>());
      expect(await da.checkIfEntityTableExists<Person>(), isTrue);
      expect(
        await da.updateSomeColumnsOf<Person>(
          <String>['lastName'],
          <String>['idPers', 'idPers'],
          <Object>['Z', 'p1', 'p2'],
          whereMcop: 'or',
        ),
        isTrue,
      );
      da.strict = true;
      expect(
        () => da.delObjet<Person>(
          <String>['idPers', 'idPers'],
          <Object>['p1', 'p2'],
          whereMcop: 'UNION',
        ),
        throwsArgumentError,
      );
    });
  });
}
