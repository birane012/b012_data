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
  b012_data: ^2.0.3
```

Then run:

```sh
flutter pub get
```

**Important note:** As soon as `b012_data` is imported in your code, a default database named `sqlf_easy.db` is automatically created in the application's documents directory specially in the databases folder. You can use the changeDB method if you don't want to use this one.

Before calling any method that needs the application documents directory
(`databasesPath`, `filesPath`, etc.), make sure the Flutter bindings are
initialized:

```dart 
import 'disc_example.dart' as disc;
import 'sqlite_example.dart' as sqlite;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // ... your app here. 
  
  // SQLite CRUD walk-through (Person entity).
  await runSqliteDemo();

  // File system / binary file walk-through (Images entity).
  await runDiscDemo();
}
```

---

## Declaring an entity and Working with the database

An entity is a plain Dart class that exposes a few well-known members used
by `DataAccess` to generate SQL statements and deserialize rows.


```dart
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
import 'package:flutter/foundation.dart';

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


/* WORKING WITH DATABASE */

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
      .updateSomeColumnsOf<Person>('firstName, lastName');
  debugPrint('First + last names: $nameRows\n');

  final List<Map<String, Object?>> womenNameRows =
      await DataAccess.instance.updateSomeColumnsOf<Person>(
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
}
```


### Things to know

1. Most entity-oriented methods throw `DatabaseException('no such table:...')`
   when the underlying table does not exist. The exceptions are
   `updateWholeObject`, `updateSomeColumnsOf`, `getAColumnFromWithTableName`
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
// -----------------------------------------------------------------------------
// b012_data — File system (binary file) manipulation example
//
// Walk-through of `DiscData.instance`: read, write, append, check, delete
// and load binary files as text, Base64, raw bytes or Flutter `Image`
// wimageIDgets (images, audio, vimageIDeo, any blob). The example also shows how
// `getEntityFileOnDisc` resolves a file name stored in an SQLite column
// back to raw bytes, so you can keep metadata in the database and the
// actual payload on disk.
//
// This file is runnable on its own via `flutter run -t example/disc_example.dart`.
// -----------------------------------------------------------------------------

import 'package:b012_data/b012_disc_data.dart';
import 'package:b012_data/b012_sqlflite_easy.dart';

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'static_and_variables.dart';

/// Metadata entity used by `getEntityFileOnDisc` to resolve an image file
/// name stored in the database and return its raw bytes. Follows the same
/// six-step convention as any b012_data entity.
class Images {
  String? imageID;
  String? imageName;
  DateTime? dateSave;
  DateTime? dateLastUpdate;

  // 1. Required: primary key declaration.
  MapEntry<String, bool> get pKeyAuto => const MapEntry('imageID', false);

  // 2. Optional: non-nullable columns, unique columns, check constraints,
  //    default values and foreign keys.
  List<String> get notNulls =>
      const <String>['imageName', 'dateSave', 'dateLastUpdate'];

  // 3. Required: unnamed constructor.
  Images([this.imageID, this.imageName, this.dateSave, this.dateLastUpdate]);

  // 4. Required: serialization to a Map.
  Map<String, dynamic> toMap() => <String, dynamic>{
        'imageID': imageID ?? ColumnType.String,
        'imageName': imageName ?? ColumnType.String,
        'dateSave': dateSave ?? ColumnType.DateTime,
        'dateLastUpdate': dateLastUpdate ?? ColumnType.DateTime,
      };

  // 5. Required: deserialization from a row.
  Images.fromMap(Map<String, Object?> json, {bool isInt = true}) {
    imageID = json['imageID'] as String?;
    imageName = json['imageName'] as String?;
    dateSave = dateTime(json['dateSave'] as String?);
    dateLastUpdate = dateTime(json['dateLastUpdate'] as String?);
  }

  // 6. Required: instance-simageIDe fromMap used by the generic getters.
  Images fromMap(Map<String, Object?> json) => Images.fromMap(json);
}


/* WORKING WITH FLIES ON FILESYSTEM */

/// Full walk-through driven exclusively through `DiscData.instance`.
/// Every path, every byte buffer and every decoded `Image` comes from the
/// application documents directory — nothing is loaded from assets.
Future<void> runDiscDemo() async {
  // -------- System paths exposed by the package --------
  // Directory that stores SQLite database files.
  final String databasesPath = await DiscData.instance.databasesPath;
  debugPrint('Databases path: $databasesPath\n');

  // Default directory where user files are saved.
  final String filesPath = await DiscData.instance.filesPath;
  debugPrint('Files path: $filesPath\n');

  // Application documents directory (the root used above).
  final String rootPath = await DiscData.instance.rootPath;
  debugPrint('Root path: $rootPath\n');

  // -------- WRITE --------
  //1. Save a text file into the default `files` directory.
  final String? savedName = await DiscData.instance.saveDataToDisc(
    'contents of test.txt',
    DataType.text,
    takeThisName: 'test.txt',
  );
  debugPrint('Saved file name: $savedName\n\n');

  // Inspect the CREATE TABLE statement generated for the Images entity.
  debugPrint('${DataAccess.instance.showCreateTable(Images())}\n\n');

  //2. CREATE — insert a single Image record into Images Table.
  final bool imageRecordCreated = await DataAccess.instance.insertObjet(
    Images('img0001', 'testImage.png', DateTime.now(), DateTime.now()),
  );
  debugPrint(
      'Image record saved in Images table on sqlf_easy.db database ? $imageRecordCreated\n');

  //1. Save an Image in base64 format to the default `files` directory.
  final String? testImage = await DiscData.instance.saveDataToDisc(
    testImageAsBase64,
    DataType.base64,
    takeThisName: 'testImage.png',
  );
  debugPrint('Image saved on disk with name: $testImage\n');

  // -------- EXISTS --------
  final bool exists = await DiscData.instance.checkFileExists(
    fileName: 'test.txt',
  );
  debugPrint('test.txt exists? $exists\n');

  // -------- READ --------
  // Read as a UTF-8 string.
  final String? asString = await DiscData.instance.readFileAsString(
    fileName: 'test.txt',
  );
  debugPrint('test.txt content: $asString\n');

  // Read as a Base64-encoded string (handy to ship blobs over JSON).
  final String? asBase64 = await DiscData.instance.readFileAsBase64(
    fileName: 'testImage.png',
  );
  debugPrint('testImage.png Base64 length: ${asBase64?.length ?? 0}\n');

  // Read as raw bytes (Uint8List) —
  // use this for any binary payload:
  // images, audio clips, vimageIDeo chunks, PDFs, etc.
  final Uint8List? asBytes = await DiscData.instance.readFileAsBytes(
    fileName: 'testImage.png',
  );
  debugPrint('testImage.png Bytes length: ${asBytes?.length ?? 0}\n');

  // Read an image file straight into a Flutter `Image` wimageIDget.
  final Image? asImage = await DiscData.instance.getImageFromDisc(
    imageName: 'testImage.png',
  );
  debugPrint('Image testImage.png loaded? ${asImage != null}\n');

  // -------- DATABASE-BACKED FILE RESOLUTION --------
  // Given a table `Images` with a column `imageName` that holds a file
  // name on disk, fetch the raw bytes of the row where `imageimageID = 1`.
  // Perfect pattern for user-uploaded media: keep metadata in SQLite,
  // keep the binary blob on disk, resolve one from the other with a
  // single call.
  final Uint8List? entityBytes = await DiscData.instance
      .getEntityFileOnDisc<Uint8List, Images>(
          'imageName', 'imageimageID', 'img0001');
  debugPrint('Image img0001 Entity file bytes: ${entityBytes?.length ?? 0}');
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
