import 'package:b012_data/b012_sqlflite_easy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common/sqlite_api.dart';

import 'support/entities.dart';
import 'support/harness.dart';
import 'support/more_entities.dart';

final DataAccess da = DataAccess.instance;

void main() {
  useSandbox();
  late List<Object> errors;
  setUp(() {
    errors = <Object>[];
    da.onError = (Object e, StackTrace s) => errors.add(e);
  });
  tearDown(() {
    da.strict = false;
    da.onError = null;
  });

  group('outside strict mode', () {
    test('a failing insert is false and reaches onError once', () async {
      expect(await da.insertObjet(Account(null, 'a@b.c', 'x')), isTrue);
      expect(await da.insertObjet(Account(null, 'a@b.c', 'y')), isFalse);
      expect(errors.single, isA<DatabaseException>());
    });

    test(
      'getAColumnFrom on a missing table is [] and reaches onError',
      () async {
        expect(await da.getAColumnFrom<String, Account>('email'), isEmpty);
        expect(errors, hasLength(1));
      },
    );

    test('getAll on an empty table is null and not an error', () async {
      await da.createTableIfNotExists(Account());
      expect(await da.getAll<Account>(Account()), isNull);
      expect(errors, isEmpty);
    });
  });

  group('in strict mode', () {
    setUp(() => da.strict = true);

    test('a failing insert throws the real error', () async {
      expect(await da.insertObjet(Account(null, 'a@b.c', 'x')), isTrue);
      await expectLater(
        da.insertObjet(Account(null, 'a@b.c', 'y')),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        da.insertObjetList(<Account>[Account(null, 'a@b.c', 'z')]),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('updates on an unknown column throw', () async {
      await da.insertObjet(Account(null, 'a@b.c', 'x'));
      await expectLater(
        da.updateSomeColumnsOf<Account>(
          <String>['unknown'],
          <String>['email'],
          <Object>[1, 'a@b.c'],
        ),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        da.updateWholeObject(
          Account(1, 'a@b.c', 'x'),
          <String>['nope'],
          <Object>[1],
        ),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('getAColumnFrom on a missing table throws', () async {
      await expectLater(
        da.getAColumnFrom<String, Account>('email'),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('"nothing found" stays null', () async {
      await da.createTableIfNotExists(Account());
      expect(await da.getAll<Account>(Account()), isNull);
      expect(await da.insertObjet(null), isFalse);
    });
  });

  group('entity getters', () {
    test('constant checks together with a boolean column', () async {
      expect(await da.insertObjet(Flag(null, true, 'x')), isTrue);
      expect(await da.insertObjet(Flag(null, true, '')), isFalse);
      expect(
        da.showCreateTable(Flag()),
        'CREATE TABLE Flag (\n'
                'id INTEGER PRIMARY KEY AUTOINCREMENT,\n'
                'on INTEGER CHECK(on IN (0, 1)),\n'
                'label TEXT CHECK(length(label) > 0)\n'
                ')'
            .replaceAll('on INTEGER CHECK(on IN', '"on" INTEGER CHECK("on" IN'),
      );
    });

    test(
      'a throwing getter is reported; the table is created without it',
      () async {
        expect(await da.insertObjet(Broken(null, null)), isTrue);
        expect(errors.single, isA<StateError>());
      },
    );

    test('a throwing getter throws in strict mode', () async {
      da.strict = true;
      expect(() => da.showCreateTable(Broken()), throwsStateError);
    });
  });
}
