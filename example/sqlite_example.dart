// -----------------------------------------------------------------------------
// b012_data — SQLite CRUD example
//
// Spring Boot-inspired walk-through of `DataAccess.instance`: you declare a
// plain Dart class (`Person`) as an entity, and b012_data automatically
// generates every CRUD statement (CREATE TABLE, INSERT, SELECT, UPDATE,
// DELETE) — no hand-written SQL, no repository boilerplate.
//
// This file is runnable on its own via `flutter run -t example/sqlite_example.dart`.
// -----------------------------------------------------------------------------

import 'package:b012_data/b012_sqlflite_easy.dart';
import 'package:flutter/material.dart';

/// A plain Dart class becomes a persisted entity by exposing the six members
/// described below. `DataAccess.instance` reads them through duck-typing to
/// build the matching SQL statements at runtime.
class Person {
  String? idPers;
  String? firstName;
  String? lastName;
  bool? sex;
  DateTime? dateOfBirth;
  // String? email;
  // String? profession;

  // 1. Required: primary key declaration.
  //    MapEntry key is the column name, value is true to use AUTOINCREMENT.
  MapEntry<String, bool> get pKeyAuto => const MapEntry('idPers', false);

  // 2. Optional: non-nullable columns, unique columns, check constraints,
  //    default values and foreign keys.
  List<String> get notNulls =>
      const <String>['firstName', 'lastName', 'sex', 'dateOfBirth'];
  // List<String> get uniques => const <String>['email'];
  // Map<String, String> get checks => const {'email': 'length(email) > 4'};
  // Map<String, String> get defaults => const {'profession': 'NULL'};
  // Map<String, List<String>> get fKeys =>
  //     const {'profession': ['Profession', 'idProf']};

  // 3. Required: an unnamed constructor used by the package to instantiate
  //    an entity before calling `fromMap` below.
  Person([
    this.idPers,
    this.firstName,
    this.lastName,
    this.sex,
    this.dateOfBirth,
  ]);

  // 4. Required: serialization to a Map.
  //    For non-nullable fields the `ColumnType` fallback can be omitted —
  //    the value will never be null at insertion time.
  Map<String, dynamic> toMap() => <String, dynamic>{
        'idPers': idPers ?? ColumnType.String,
        'firstName': firstName ?? ColumnType.String,
        'lastName': lastName ?? ColumnType.String,
        'sex': sex ?? ColumnType.bool,
        'dateOfBirth': dateOfBirth ?? ColumnType.DateTime,
      };

  // 5. Required: deserialization from a row.
  Person.fromMap(Map<String, Object?> json, {bool isInt = true}) {
    idPers = json['idPers'] as String?;
    firstName = json['firstName'] as String?;
    lastName = json['lastName'] as String?;
    sex = boolean(json['sex'], isInt: isInt) as bool?;
    dateOfBirth = dateTime(json['dateOfBirth'] as String?);
  }

  // 6. Required: instance-side fromMap used by the generic getters.
  Person fromMap(Map<String, Object?> json) => Person.fromMap(json);
}

/// Full CRUD walk-through driven exclusively through `DataAccess.instance`.
/// Every call below is the high-level equivalent of a Spring Data JPA
/// repository method — no SQL string is ever written by hand.
Future<void> runSqliteDemo() async {
  // Inspect the CREATE TABLE statement generated for the Person entity.
  debugPrint('${DataAccess.instance.showCreateTable(Person())}\n\n');

  // Does the Person table already exist in the database?
  final bool personTableExists =
      await DataAccess.instance.checkIfEntityTableExists<Person>();
  debugPrint('Person table exists? $personTableExists\n');

  // CREATE — insert a single Person row.
  final bool inserted = await DataAccess.instance.insertObjet(
    Person(newKey, 'KEBE', 'Birane', true, DateTime(2000, 8, 5)),
  );
  debugPrint('Single insert ok? $inserted\n');

  // CREATE (bulk) — insert several Persons inside a single transaction.
  final bool personsListInserted =
      await DataAccess.instance.insertObjetList(<Person>[
    Person(newKey, 'Mbaye', 'Aliou', true, DateTime(1999, 5, 1)),
    Person(newKey, 'Cisse', 'Fatou', false, DateTime(2000, 7, 9)),
  ]);
  debugPrint('Bulk insert ok? $personsListInserted\n');

  // READ — fetch a single row matching an SQL predicate.
  final Person? birane = await DataAccess.instance.get<Person>(
    Person(),
    "firstName = 'Birane' AND lastName = 'KEBE'",
  );
  debugPrint('Found Birane? ${birane != null}\n');

  // READ — fetch every row.
  final List<Person>? everyone = await DataAccess.instance.getAll<Person>(
    Person(),
  );
  debugPrint('Total persons: ${everyone?.length ?? 0}\n');

  // READ — fetch rows matching a predicate. Booleans are automatically
  // converted to 0/1 for SQLite, so `sex = true` is equivalent to `sex = 1`.
  final List<Person>? men = await DataAccess.instance.getAllSorted<Person>(
    Person(),
    'sex = true',
  );
  debugPrint('Men: ${men?.length ?? 0}\n');

  // READ (projection) — pull a single column across the whole table.
  final List<String> firstNames =
      await DataAccess.instance.getAColumnFrom<String, Person>('firstName');
  debugPrint('First names: $firstNames\n');

  final List<String> womenFirstNames = await DataAccess.instance
      .getAColumnFrom<String, Person>('firstName', afterWhere: 'sex = false');
  debugPrint('Women first names: $womenFirstNames\n');

  // READ (projection) — pull several columns at once.
  final List<Map<String, Object?>> nameRows = await DataAccess.instance
      .getSomeColumnsFrom<Person>('firstName, lastName');
  debugPrint('First + last names: $nameRows\n');

  final List<Map<String, Object?>> womenNameRows =
      await DataAccess.instance.getSomeColumnsFrom<Person>(
    'firstName, lastName',
    afterWhere: 'sex = 0',
  );
  debugPrint('Women first + last names: $womenNameRows\n');

  // UPDATE — values follow the order `columnsToUpadate` + `whereColumns`.
  // Here: set `firstName = 'developer'` and `lastName = '2022'` where
  // `firstName = 'Birane' AND lastName = 'KEBE'`.
  final bool updated = await DataAccess.instance.updateSomeColumnsOf<Person>(
    <String>['firstName', 'lastName'],
    <String>['firstName', 'lastName'],
    <Object>['developer', '2022', 'Birane', 'KEBE'],
  );
  debugPrint('Update ok? $updated\n');

  // DELETE — remove every row matching the predicate.
  final bool deletedFatou = await DataAccess.instance.deleteObjet<Person>(
    "firstName = 'Fatou'",
  );
  debugPrint('Fatou deleted? $deletedFatou\n');

  // COUNT — total rows and filtered rows.
  final int total = await DataAccess.instance.countElementsOf<Person>();
  final int males = await DataAccess.instance.countElementsOf<Person>(
    afterWhere: 'sex = true',
  );
  debugPrint('Total rows: $total, male rows: $males\n');

  // Attention: The following instruction drops every table in the sqlf_easy.db database (tables stay, rows are removed).
  // await DataAccess.instance.cleanAllTablesData();

  // Things to know:
  // 1. Most entity-oriented methods throw
  //    `DatabaseException('no such table: ...')` when the underlying table
  //    does not exist. The exceptions are `updateWholeObject`,
  //    `updateSomeColumnsOf`, `getAColumnFromWithTableName` and
  //    `getAColumnFrom`, which catch the error and only log it via
  //    `debugPrint`. Wrap the other methods in `try` / `catch` if you are
  //    not sure the table already exists.
  // 2. `insertObjet` and `insertObjetList` internally convert your entity
  //    map using `mapToUse(entity.toMap())`. Call
  //    `mapToUse(entity.toMap(), forDB: false)` yourself when you want a
  //    plain Dart map (e.g. for JSON serialization or display) instead of
  //    an SQLite-ready one.
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // SQLite CRUD walk-through (Person entity).
  await runSqliteDemo();

  runApp(
    const MaterialApp(
      home:
          Scaffold(body: Center(child: Text('runSqliteDemo tests completed'))),
    ),
  );
}
