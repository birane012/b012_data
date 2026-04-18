# b012_data

`b012_data` is a Flutter package focused on **data manipulation**, inspired by
the **Spring Boot** framework: declare a plain Dart class as an entity and the
package automatically generates every **CRUD** operation (create, read, update,
delete) on your local SQLite database — no hand-written SQL, no boilerplate
repository.

* Object persistence on a local **SQLite** database, via `DataAccess.instance`.
* File system helpers (read, write, append, check, delete, load binary files as images, audios, videos and so on), via `DiscData.instance`.

Supported platforms: **Android, iOS, macOS, Linux, Windows**.

> On mobile platforms (Android, iOS, macOS) the package uses the native
> [`sqflite`](https://pub.dev/packages/sqflite) implementation.
> On desktop platforms (Linux, Windows) it transparently falls back to
> [`sqflite_common_ffi`](https://pub.dev/packages/sqflite_common_ffi).

More details and a longer walk-through can be found at
<https://birane012.github.io>.

---

## Installation

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  b012_data: ^2.0.2
```

Then run:

```sh
flutter pub get
```

Before calling any method that needs the application documents directory
(`databasesPath`, `filesPath`, etc.), make sure the Flutter bindings are
initialized:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // ... your app here
}
```

---

## Declaring an entity

An entity is a plain Dart class that exposes a few well-known members used
by `DataAccess` to generate SQL statements and deserialize rows.

```dart
import 'package:b012_data/b012_sqlflite_easy.dart';

//Person entity
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
      <String>['firstName', 'lastName', 'sex', 'dateOfBirth'];
  // List<String> get uniques => <String>['email'];
  // Map<String, String> get checks => {'email': 'length(email) > 4'};
  // Map<String, String> get defaults => {'profession': 'NULL'};
  // Map<String, List<String>> get fKeys =>
  //     {'profession': ['Profession', 'idProf']};

  // 3. Required: an unnamed constructor used by the package to instantiate
  //    an entity from the `fromMap` method below.
  Person([this.idPers, this.firstName, this.lastName, this.sex, this.dateOfBirth]);

  // 4. Required: serialization to a Map.
  //    For non-nullable fields the `ColumnType` fallback can be omitted —
  //    the value will never be null at insertion time.
  Map<String, dynamic> toMap() => {
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
    sex = boolean(json['sex'], isInt: isInt);
    dateOfBirth = dateTime(json['dateOfBirth'] as String?);
  }

  // 6. Required: instance-side fromMap used by the generic getters.
  Person fromMap(Map<String, Object?> json) => Person.fromMap(json);
}
```

---

## Working with the database

```dart
import 'package:b012_data/b012_sqlflite_easy.dart';
import 'package:flutter/foundation.dart';

Future<void> example() async {
  // Inspect the CREATE TABLE statement generated for Person.
  debugPrint(DataAccess.instance.showCreateTable(Person()));

  // Does the Person table already exist?
  final exists = await DataAccess.instance.checkIfEntityTableExists<Person>();

  // Insert a single Person.
  final inserted = await DataAccess.instance.insertObjet(
    Person(newKey, 'KEBE', 'Birane', true, DateTime(2000, 8, 5)),
  );

  // Insert several Persons in a single transaction.
  final bulk = await DataAccess.instance.insertObjetList(<Person>[
    Person(newKey, 'Mbaye', 'Aliou', true, DateTime(1999, 5, 1)),
    Person(newKey, 'Cisse', 'Fatou', false, DateTime(2000, 7, 9)),
  ]);

  // Fetch a single row.
  final Person? birane = await DataAccess.instance
      .get<Person>(Person(), "firstName = 'Birane' AND lastName = 'KEBE'");

  // Fetch every row.
  final List<Person>? all = await DataAccess.instance.getAll<Person>(Person());

  // Fetch rows matching a predicate. Booleans are automatically converted
  // to 0/1 for SQLite.
  final List<Person>? men = await DataAccess.instance
      .getAllSorted<Person>(Person(), 'sex = true');

  // Project a single column.
  final List<String> firstNames = await DataAccess.instance
      .getAColumnFrom<String, Person>('firstName');

  final List<String> womenFirstNames = await DataAccess.instance
      .getAColumnFrom<String, Person>('firstName', afterWhere: 'sex = false');

  // Project multiple columns.
  final rows = await DataAccess.instance
      .getSommeColumnsFrom<Person>('firstName, lastName');

  final womenRows = await DataAccess.instance.getSommeColumnsFrom<Person>(
    'firstName, lastName',
    afterWhere: 'sex = 0',
  );

  // Update rows. Values follow the order of `columnsToUpadate` + `whereColumns`.
  final updated = await DataAccess.instance.updateSommeColumnsOf<Person>(
    ['firstName', 'lastName'],
    ['firstName', 'lastName'],
    ['developer', '2022', 'Birane', 'KEBE'],
  );

  // Delete rows matching a predicate.
  final deleted = await DataAccess.instance
      .deleteObjet<Person>("firstName = 'Fatou'");

  // Count rows.
  final total = await DataAccess.instance.countElementsOf<Person>();
  final males = await DataAccess.instance
      .countElementsOf<Person>(afterWhere: 'sex = true');

  // Wipe every user-defined table (tables stay, rows are removed).
  await DataAccess.instance.cleanAllTablesData();
}
```

### Things to know

1. Most entity-oriented methods throw `DatabaseException('no such table:...')`
   when the underlying table does not exist. The exceptions are
   `updateWholeObject`, `updateSommeColumnsOf`, `getAColumnFromWithTableName`
   and `getAColumnFrom`, which catch the error and only log it via
   `debugPrint`. Wrap the other methods in `try` / `catch` if you are not
   sure the table already exists.
2. `insertObjet` and `insertObjetList` internally convert your entity map
   using `mapToUse(entity.toMap())`. Call `mapToUse(entity.toMap(), forDB: false)`
   yourself when you want a plain Dart map (e.g. for JSON serialization or
   display) instead of an SQLite-ready one.

---

## Working with files on disk

```dart
import 'dart:typed_data';
import 'package:b012_data/b012_disc_data.dart';
import 'package:flutter/widgets.dart';

Future<void> fileExample() async {
  // System paths exposed by the package.
  final databasesPath = await DiscData.instance.databasesPath;
  final filesPath = await DiscData.instance.filesPath;
  final rootPath = await DiscData.instance.rootPath;

  // Write text to disk inside `filesPath`.
  final fileName = await DiscData.instance.saveDataToDisc(
    'hello world',
    DataType.text,
    takeThisName: 'test.txt',
  );

  // Check existence.
  final exists = await DiscData.instance.checkFileExists(fileName: 'test.txt');

  // Read as text / base64 / bytes / Image.
  final String? text =
      await DiscData.instance.readFileAsString(fileName: 'test.txt');
  final String? base64 =
      await DiscData.instance.readFileAsBase64(fileName: 'my_image.png');
  final Uint8List? bytes =
      await DiscData.instance.readFileAsBytes(fileName: 'my_image.png');
  final Image? image =
      await DiscData.instance.getImageFromDisc(imageName: 'my_image.png');

  // Load a file whose name is stored in a column of an SQLite table.
  // Given a table `Images` with a column `imageName`, fetch the bytes of
  // the image referenced by the row where `imageID = 1`:
  final Uint8List? imageBytes = await DiscData.instance
      .getEntityFileOnDisc<Uint8List, Images>('imageName', 'imageID', 1);
}
```

---

## Full worked example

The [`example/`](example) folder splits the two concerns into self-contained,
runnable files so each API can be explored in isolation:

* [`example/sqlite_example.dart`](example/sqlite_example.dart) — SQLite CRUD
  demo built around the `Person` entity and `DataAccess.instance`.
  Run it alone with `flutter run -t example/sqlite_example.dart`.
* [`example/disc_example.dart`](example/disc_example.dart) — File system /
  binary file demo (text, Base64, raw bytes, `Image`) built around
  `DiscData.instance` and the `Images` entity.
  Run it alone with `flutter run -t example/disc_example.dart`.
* [`example/main.dart`](example/main.dart) — Entry point that runs both
  demos in sequence.

---

## License

Published under the terms of the included [`LICENSE`](LICENSE) file.
