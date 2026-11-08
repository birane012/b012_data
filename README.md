# b012_data

`b012_data` is a Flutter package focused on **data manipulation**, inspired by
the **Spring Boot** framework: declare a plain Dart class as an entity and the
package automatically generates every **CRUD** operation (create, read, update,
delete) on your local SQLite database — no hand-written SQL, no boilerplate
repository.

* Object persistence on a local **SQLite** database, via `DataAccess.instance`.
* File system helpers (read, write, append, check, delete, load binary files as images, audios, videos and so on), via `DiscData.instance`.

Supported platforms: **Android, iOS, macOS, Linux, Windows and web**.
Optional encryption of the database and of the files (2.1).

> On mobile platforms (Android, iOS, macOS) the package uses the native
> [`sqflite`](https://pub.dev/packages/sqflite) implementation.
> On desktop platforms (Linux, Windows) it transparently falls back to
> [`sqflite_common_ffi`](https://pub.dev/packages/sqflite_common_ffi).
> In a browser it runs SQLite as WebAssembly with
> [`sqlite3`](https://pub.dev/packages/sqlite3) (see [Web](#web)).

More details and a longer walk-through can be found at
<https://birane012.github.io>.

---

## Installation

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  b012_data: ^2.1.0
```

Then run:

```sh
flutter pub get
```

2.1 requires Dart 3.12 and Flutter 3.44 or later (the current `sqflite`
packages do); an application on an older Flutter keeps resolving 2.0.3.

**Important note:** The first access creates a default database named `sqlf_easy.db` in the application's databases folder (see [Where your data lives](#where-your-data-lives)). You can use the changeDB method if you don't want to use this one.

Before calling any method that needs the application documents directory
(`databasesPath`, `filesPath`, etc.), make sure the Flutter bindings are
initialized:

```dart 
import 'disc_example.dart' as disc;
import 'sqlite_example.dart' as sqlite;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // ... your app here, like below.
  
  // SQLite CRUD walk-through (Person entity).
  await sqlite.runSqliteDemo();

  // File system / binary file walk-through (Images entity).
  await disc.runDiscDemo();
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
/// repository method: at most you write a WHERE condition, whose values are
/// passed in `whereArgs` and bound to its `?` placeholders.
Future<void> runSqliteDemo() async {
  // Inspect the CREATE TABLE statement generated for the Person entity.
  debugPrint('${DataAccess.instance.showCreateTable(Person())}\n\n');

  // Does the Person table already exist in the database?
  final bool personTableExists = await DataAccess.instance
      .checkIfEntityTableExists<Person>();
  debugPrint('Person table exists? $personTableExists\n');

  // CREATE — insert a single Person row.
  final bool inserted = await DataAccess.instance.insertObjet(
    Person(newKey, 'Birane', 'KEBE', true, DateTime(2000, 8, 5)),
  );
  debugPrint('Single insert ok? $inserted\n');

  // CREATE (bulk) — insert several Persons in one call. If a row fails, the
  // rows before it are kept: call it inside `transaction` for all or nothing.
  final bool personsListInserted = await DataAccess.instance
      .insertObjetList(<Person>[
        Person(newKey, 'Aliou', 'Mbaye', true, DateTime(1999, 5, 1)),
        Person(newKey, 'Fatou', 'Cisse', false, DateTime(2000, 7, 9)),
      ]);
  debugPrint('Bulk insert ok? $personsListInserted\n');

  // READ — fetch a single row. Each `?` is bound to the matching value of
  // `whereArgs`: a value is never pasted into the SQL text.
  final Person? birane = await DataAccess.instance.get<Person>(
    Person(),
    'firstName = ? AND lastName = ?',
    <Object>['Birane', 'KEBE'],
  );
  debugPrint('Found Birane? ${birane != null}\n');

  // READ — fetch every row.
  final List<Person>? everyone = await DataAccess.instance.getAll<Person>(
    Person(),
  );
  debugPrint('Total persons: ${everyone?.length ?? 0}\n');

  // READ — fetch the rows matching a condition. Booleans and dates are bound
  // the way b012_data stores them (`true` is stored as 1).
  final List<Person>? men = await DataAccess.instance.getAllSorted<Person>(
    Person(),
    'sex = ?',
    <Object>[true],
  );
  debugPrint('Men: ${men?.length ?? 0}\n');

  // READ (projection) — pull a single column across the whole table.
  final List<String> firstNames = await DataAccess.instance
      .getAColumnFrom<String, Person>('firstName');
  debugPrint('First names: $firstNames\n');

  final List<String> womenFirstNames = await DataAccess.instance
      .getAColumnFrom<String, Person>(
        'firstName',
        afterWhere: 'sex = ?',
        whereArgs: <Object>[false],
      );
  debugPrint('Women first names: $womenFirstNames\n');

  // READ (projection) — pull several columns at once.
  final List<Map<String, Object?>> nameRows = await DataAccess.instance
      .getSomeColumnsFrom<Person>('firstName, lastName');
  debugPrint('First + last names: $nameRows\n');

  final List<Map<String, Object?>> womenNameRows = await DataAccess.instance
      .getSomeColumnsFrom<Person>(
        'firstName, lastName',
        afterWhere: 'sex = ?',
        whereArgs: <Object>[false],
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

  // DELETE — remove every row matching the condition.
  final bool deletedFatou = await DataAccess.instance.deleteObjet<Person>(
    'firstName = ?',
    <Object>['Fatou'],
  );
  debugPrint('Fatou deleted? $deletedFatou\n');

  // COUNT — total rows and filtered rows.
  final int total = await DataAccess.instance.countElementsOf<Person>();
  final int males = await DataAccess.instance.countElementsOf<Person>(
    afterWhere: 'sex = ?',
    whereArgs: <Object>[true],
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
   `debugPrint` (and `onError`) — unless `strict` is set. Wrap the other
   methods in `try` / `catch` if you are not sure the table already exists.
2. `afterWhere` texts are inserted as is: never build them from user input,
   use `?` and `whereArgs` (see [Security](#security-bound-values)).
3. `insertObjet` and `insertObjetList` internally convert your entity map
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

## What's new in 2.1

2.1 hardens the package without changing how you use it: every method of
2.0.3 keeps its name, its parameters and its default behaviour (including
returning `false`, `null` or `[]` on failure). Everything new is opt-in.

### Security: bound values

`afterWhere` is inserted as is after `WHERE` (that is what lets you write
`ORDER BY` and `LIMIT` in it): **never build it from user input**. Put `?`
placeholders in it and pass the values in `whereArgs` instead — booleans and
dates are bound exactly as b012_data stores them:

```dart
final Person? p = await DataAccess.instance.get<Person>(
  Person(),
  'lastName = ? AND sex = ?',
  [userInput, true],
);
final int n = await DataAccess.instance.countElementsOf<Person>(
  afterWhere: 'dateOfBirth >= ?',
  whereArgs: [DateTime(2000)],
);
```

Every `afterWhere` method accepts `whereArgs` (positional after
`afterWhere` for `get`, `getAllSorted` and `deleteObjet`, named otherwise).
The queries the package builds itself (`getLogin`, `checkIfTableExists`,
`getEntityFileOnDisc`, ...) always bind their values. Table and column names
that are SQL keywords (`order`, `group`, ...) are quoted for you; in your own
`afterWhere` text, quote them yourself (`'"group" = ?'`). `whereMcop` accepts
only `AND` and `OR`.

### Errors: strict mode

```dart
DataAccess.instance.strict = true;          // throw the real error
DataAccess.instance.onError = (e, s) => log(e); // or just be told
```

With `strict`, a failing insert or update throws the real `DatabaseException`
instead of returning `false`; "nothing found" is still `null` or `[]`.
Without it, every error turned into `false` or `[]` is still printed with
`debugPrint` and also passed to `onError`.

### Transactions

```dart
await DataAccess.instance.transaction(() async {
  await DataAccess.instance.insertObjet(order);
  await DataAccess.instance.updateSomeColumnsOf<Stock>(['qty'], ['id'], [qty - 1, id]);
}); // everything or nothing
```

Every `DataAccess` method called inside takes part in the transaction; a
transaction started inside a transaction joins it. Inside a transaction a
failing method throws (even outside strict mode) instead of returning
`false`, so that everything is rolled back. Outside a transaction,
`insertObjetList` keeps its 2.0.3 behaviour (rows before a failing one are
kept).

### Replace, keys, indexes

```dart
await DataAccess.instance.insertObjet(person, orReplace: true); // INSERT OR REPLACE
```

New optional entity getters:

```dart
List<String> get pKeys => ['maintenanceId', 'technicianId'];   // composite key
Map<String, List<String>> get indexes => {'assignment_trade': ['trade']};
Map<String, List<String>> get uniqueIndexes => {'one_trade': ['maintenanceId', 'trade']};
```

Indexes are created when missing, also on an existing table.

### Stable table names

A table is named after its class. Obfuscated builds (and web release
builds) change class names, so register the entities whose name must not
move:

```dart
DataAccess.instance.registerEntity<Person>('person');
```

Every method follows the registration, including the ones that only receive
the type (`countElementsOf<Person>()`). **In a browser, registration is
required.**

### Schema evolution and migrations

```dart
DataAccess.instance.autoAddColumns = true; // new entity columns are added
DataAccess.instance.migrations = {
  2: () => DataAccess.instance.rawExecute('UPDATE person SET sex = 0 WHERE sex IS NULL'),
  3: () async { /* ... */ },
};
```

With `autoAddColumns` (off by default), a column added to an entity is added
to its table (`ALTER TABLE ... ADD COLUMN`); columns are never dropped or
renamed. Migrations run once each when the database opens, in order, each in
its own transaction that sets `PRAGMA user_version`; a failing step is rolled
back and makes the opening fail. Set both before the first access.

### Queries

```dart
final List<Person> page = await DataAccess.instance.query<Person>(
  Person(),
  where: 'sex = ?',
  whereArgs: [true],
  orderBy: 'lastName',
  limit: 20,
  offset: 40,
); // [] when nothing matches
final rows = await DataAccess.instance.rawQuery('SELECT ... WHERE x = ?', [x]);
final people = await DataAccess.instance.rawQueryAs<Person>(Person(), 'SELECT ...');
final changed = await DataAccess.instance.rawExecute('UPDATE ... WHERE id = ?', [id]);
```

### Foreign keys

`fKeys` were declared but never enforced. Set
`DataAccess.instance.enforceForeignKeys = true` before the first access to
enforce them (`PRAGMA foreign_keys = ON`). It is off by default because
enforcing them could break an application that inserts a child before its
parent.

### Where your data lives

* **Android, iOS, macOS**: exactly as in 2.0.3.
* **Windows, Linux**: 2.0.3 created the database under the *current
  directory* (`.dart_tool/sqflite_common_ffi/databases`), so launching the
  application from another folder opened another database, and the `dbName`
  file and the files folder were shared by every application of the
  computer. 2.1 keeps a new installation's databases, `dbName` and files in
  the application support folder. A database left by 2.0.3 is found and kept
  where it is (its absolute path is recorded), so nothing disappears; an
  application in that case keeps its 2.0.3 files folder (and its 2.0.3
  `databasesPath`) too. For a new installation, files saved by 2.0.3 in the
  shared folder stay readable by name, but are never modified or deleted
  through it. The decision is taken once and does not change afterwards.
* `changeDB` creates the folder it needs.

### Files

Files are read and written asynchronously. A file is written to a temporary
file, flushed, then renamed over the target: a reader never sees half of it.
A file *name* can no longer point outside `filesPath` (`'../x'` throws an
`ArgumentError`); explicit absolute paths work as before.

### Web

The same API runs in a browser:

```sh
dart run b012_data:setup_web   # puts sqlite3mc.wasm and sqlite3.wasm in web/
```

* SQLite runs as WebAssembly (`sqlite3mc.wasm` by default; set
  `DataAccess.instance.webSqliteWasmUri` to use another module). Databases
  and `DiscData` files live in IndexedDB; persistent storage is requested.
* Every write is stored in IndexedDB before its future completes.
* One tab at a time: a second tab opening the same database gets a clear
  `StateError` instead of a copy that would overwrite the first; the storage
  is read only once the tab holds the database, so it always sees the other
  tab's last writes. This needs the Web Locks API, available on `https` and
  `localhost`.
* Entities must be registered (`registerEntity`).
* `DataAccess.db` and `openDB` (sqflite objects) are not available;
  `DiscData.getFile` returns `null` (there is no file system).
* A browser can still erase site data when the user clears it.

### Encryption

Against a lost or stolen device, the database and the files saved by name
can be encrypted with [SQLite3MultipleCiphers](https://github.com/utelle/SQLite3MultipleCiphers)
(MIT licence). Choose this engine in **your application's** `pubspec.yaml`:

```yaml
hooks:
  user_defines:
    sqlite3:
      source: sqlite3mc
```

(in a browser, `setup_web` already provides `sqlite3mc.wasm`). Then:

```dart
await DataAccess.instance.useEncryptionKey(key);      // before the first access
await DataAccess.instance.encryptDatabase(key);       // encrypt an existing plaintext database in place
await DataAccess.instance.changeEncryptionKey(newKey);
```

* A new database is created encrypted; a wrong key throws a `StateError`.
* The engine is checked first: if it does not encrypt, a `StateError` says
  what to add to `pubspec.yaml`. A database is never created in plaintext by
  mistake.
* A key given for an existing plaintext database is refused (use
  `encryptDatabase`); an encrypted database is never opened without its key
  (on Android the system SQLite would take it for a corrupt file and erase
  it).
* Files saved by name with `DiscData` are encrypted (AES-256-GCM) with a
  random key kept inside the encrypted database, so changing the database key
  rewrites no file. Files written at an explicit path (exports) stay plain
  unless `saveDataToDisc(..., encrypt: true)`. Older plaintext files remain
  readable. `encryptDatabase` encrypts the files `DiscData` saved by name
  since 2.1 (it keeps their list) and the names you pass in `alsoFiles`;
  nothing else in the files folder is touched (on Android it is shared with
  other plugins). A file is encrypted with the key of the database open when
  it is saved: an application that switches between encrypted databases
  with `changeDB` reads each file with the database that saved it.
* On Android and iOS an encrypted database goes through the engine bundled
  by `package:sqlite3`, not the system SQLite.
* **b012_data never stores the key**: your application provides it at each
  start. On a device, keep a random key in the system vault (Keystore,
  Keychain, Windows data protection) and unlock it however your application
  authenticates its user. In a browser there is no vault: the key must come
  from something the user types, or the encryption protects nothing.

### Tested platforms

2.1 was tested on Windows (unit tests, real SQLite3MultipleCiphers), in
Chrome (a check application in `tool/web_check`) and on an Android emulator.
iOS, macOS and Linux share the same code paths but were not run.

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
* [`example/whats_new_example.dart`](example/whats_new_example.dart) — the
  2.1 additions: registration, bound values, transactions, queries, replace.
  Run it alone with `flutter run -t example/whats_new_example.dart`.
* [`example/main.dart`](example/main.dart) — Entry point that runs the
  demos in sequence.

---

## License

Published under the terms of the included [`LICENSE`](LICENSE) file.
