// The minor findings of the final review, pinned before their fixes.
import 'package:b012_data/b012_disc_data.dart';
import 'package:b012_data/b012_sqlflite_easy.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';
import 'support/limit_entities.dart';

final DataAccess da = DataAccess.instance;
final DiscData disc = DiscData.instance;

/// Declares an index named like Assignment's, on another table.
class Clash {
  Clash([this.id, this.trade]);

  Clash.fromMap(Map<String, Object?> m)
    : id = m['id'] as int?,
      trade = m['trade'] as String?;

  int? id;
  String? trade;

  Map<String, List<String>> get uniqueIndexes => const <String, List<String>>{
    'assignment_trade': <String>['trade'],
  };

  Map<String, dynamic> toMap() => <String, dynamic>{
    'id': id ?? ColumnType.int,
    'trade': trade ?? ColumnType.String,
  };

  Clash fromMap(Map<String, Object?> m) => Clash.fromMap(m);
}

/// A getter that exists but fails with a NoSuchMethodError of its own.
class Sneaky {
  Sneaky([this.id]);

  Sneaky.fromMap(Map<String, Object?> m) : id = m['id'] as int?;

  int? id;

  List<String> get notNulls => (null as dynamic).cast<String>() as List<String>;

  Map<String, dynamic> toMap() => <String, dynamic>{'id': id ?? ColumnType.int};

  Sneaky fromMap(Map<String, Object?> m) => Sneaky.fromMap(m);
}

/// ContactV1 with its column renamed by case only.
class ContactCase {
  ContactCase([this.id, this.Name]);

  ContactCase.fromMap(Map<String, Object?> m)
    : id = m['id'] as int?,
      Name = m['Name'] as String?;

  int? id;
  // ignore: non_constant_identifier_names
  String? Name;

  MapEntry<String, bool> get pKeyAuto => const MapEntry('id', true);

  Map<String, dynamic> toMap() => <String, dynamic>{
    'id': id ?? ColumnType.int,
    'Name': Name ?? ColumnType.String,
  };

  ContactCase fromMap(Map<String, Object?> m) => ContactCase.fromMap(m);
}

void main() {
  useSandbox();
  late List<Object> errors;
  setUp(() {
    errors = <Object>[];
    da.onError = (Object e, StackTrace s) => errors.add(e);
  });
  tearDown(() async {
    da.onError = null;
    da.strict = false;
    da.autoAddColumns = false;
    da.enforceForeignKeys = false;
    da.debugClearRegistry();
    await da.useEncryptionKey(null);
    await da.closeDB();
  });

  test('M4 an index name already used by another table is refused', () async {
    expect(await da.insertObjet(Assignment('m1', 't1', 'elec')), isTrue);
    await expectLater(da.createTableIfNotExists(Clash()), throwsStateError);
  });

  test('M7 cleanAllTablesData works with enforced foreign keys', () async {
    da.enforceForeignKeys = true;
    await da.closeDB();
    await da.insertObjet(Parent(1));
    await da.insertObjet(Child(null, 1));
    await da.cleanAllTablesData();
    expect(await da.countElementsOf<Child>(), 0);
    expect(await da.countElementsOf<Parent>(), 0);
  });

  test(
    'M10 a NoSuchMethodError inside an existing getter is reported',
    () async {
      await da.createTableIfNotExists(Sneaky());
      expect(errors.single, isA<NoSuchMethodError>());
    },
  );

  test('M11 a column renamed by case only does not break inserts', () async {
    da.registerEntity<ContactV1>('contact');
    da.registerEntity<ContactCase>('contact');
    await da.insertObjet(ContactV1(null, 'Awa'));
    da.autoAddColumns = true;
    await da.closeDB();
    expect(await da.insertObjet(ContactCase(null, 'Moussa')), isTrue);
  });

  test('a file sealed by another database says so clearly', () async {
    await da.useEncryptionKey('k1');
    await disc.saveDataToDisc('a', DataType.text, takeThisName: 'a.txt');
    try {
      await da.changeDB('autre');
      await expectLater(
        disc.readFileAsString(fileName: 'a.txt'),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('another'),
          ),
        ),
      );
    } finally {
      // Leave no encrypted base behind for the next tests.
      await da.changeDB('sqlf_easy');
      await disc.deleteFile(fileName: 'a.txt');
      final String path = (await da.db).path;
      await da.useEncryptionKey(null);
      await da.dropDB(path);
    }
  });

  test('M3 a migration step already applied is not run again', () async {
    int runs = 0;
    da.migrations = <int, Future<void> Function()>{1: () async => runs++};
    await da.closeDB();
    await Future.wait(<Future<Object?>>[
      da.rawQuery('SELECT 1'),
      da.changeDB('sqlf_easy'),
    ]);
    expect(runs, 1);
    da.migrations = <int, Future<void> Function()>{};
  });
}
