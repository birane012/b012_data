import 'dart:typed_data';

import 'package:b012_data/b012_disc_data.dart';
import 'package:b012_data/b012_sqlflite_easy.dart';
import 'package:flutter/material.dart';

// Person entity
class Person {
  String? idPers;
  String? firstName;
  String? lastName;
  bool? sex;
  DateTime? dateOfBirth;
  // String? email;
  // String? profession;

  // Step 1: primary key declaration (required).
  // The MapEntry key is the column name; set the value to `true` to turn
  // the key into an AUTOINCREMENT column.
  MapEntry<String, bool> get pKeyAuto => const MapEntry('idPers', false);

  // Optional: list of columns that must not be NULL.
  List<String> get notNulls =>
      const <String>['firstName', 'lastName', 'sex', 'dateOfBirth'];

  // Optional: columns that must hold unique values.
  // List<String> get uniques => const <String>['email'];

  // Optional: SQL CHECK constraints, one per column.
  // Map<String, String> get checks => const {'email': 'length(email) > 4'};

  // Optional: default value assigned to a column when none is provided.
  // Map<String, String> get defaults => const {'profession': 'NULL'};

  // Optional: foreign keys. For each field, the list holds
  // [referenced table name, referenced column name].
  // Map<String, List<String>> get fKeys =>
  //     const {'profession': ['Profession', 'idProf']};

  // Step 2: unnamed constructor (required).
  // The package uses it to instantiate an entity before calling `fromMap`.
  Person([
    this.idPers,
    this.firstName,
    this.lastName,
    this.sex,
    this.dateOfBirth,
  ]);

  // Step 3: serialization to a Map (required).
  // For non-nullable fields you may omit the `ColumnType` fallback since
  // the value will never be null at insertion time.
  Map<String, dynamic> toMap() => <String, dynamic>{
        'idPers': idPers ?? ColumnType.String,
        'firstName': firstName ?? ColumnType.String,
        'lastName': lastName ?? ColumnType.String,
        'sex': sex ?? ColumnType.bool,
        'dateOfBirth': dateOfBirth ?? ColumnType.DateTime,
      };

  // Step 4: named `fromMap` constructor (required).
  // Deserializes a row (`Map<String, Object?>`) into a fresh instance.
  Person.fromMap(Map<String, Object?> json, {bool isInt = true}) {
    idPers = json['idPers'] as String?;
    firstName = json['firstName'] as String?;
    lastName = json['lastName'] as String?;
    sex = boolean(json['sex'], isInt: isInt) as bool?;
    dateOfBirth = dateTime(json['dateOfBirth'] as String?);
  }

  // Step 5: instance-side `fromMap` (required).
  // Used by the generic getters to hydrate a returned row.
  Person fromMap(Map<String, Object?> json) => Person.fromMap(json);
}

////////////////////////////////// Usage examples //////////////////////////////////

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  /////////// DataAccess.instance /////////////

  // Print the CREATE TABLE statement generated for the Person entity.
  debugPrint(DataAccess.instance.showCreateTable(Person()));

  // Check whether the Person table already exists in the database.
  final bool witnessPersTableExiste =
      await DataAccess.instance.checkIfEntityTableExists<Person>();
  debugPrint('Person table exists? $witnessPersTableExiste');

  // Insert a new Person row into the Person table.
  final bool tInsert = await DataAccess.instance.insertObjet(
    Person(newKey, 'KEBE', 'Birane', true, DateTime(2000, 8, 5)),
  );
  debugPrint('Single insert ok? $tInsert');

  // Insert a list of Person rows into the Person table.
  final bool tInsertList = await DataAccess.instance.insertObjetList(<Person>[
    Person(newKey, 'Mbaye', 'Aliou', true, DateTime(1999, 5, 1)),
    Person(newKey, 'Cisse', 'Fatou', false, DateTime(2000, 7, 9)),
  ]);
  debugPrint('Bulk insert ok? $tInsertList');

  // Fetch a single Person matching the given SQL predicate.
  final Person? birane = await DataAccess.instance
      .get<Person>(Person(), "firstName = 'Birane' AND lastName = 'KEBE'");
  debugPrint('Found Birane? ${birane != null}');

  // Fetch every Person stored in the Person table.
  final List<Person>? persons =
      await DataAccess.instance.getAll<Person>(Person());
  debugPrint('Total persons: ${persons?.length ?? 0}');

  // Fetch every male Person in the Person table.
  final List<Person>? men =
      await DataAccess.instance.getAllSorted<Person>(Person(), 'sex = 1');
  debugPrint('Men: ${men?.length ?? 0}');

  // Project the `firstName` column across every Person row.
  final List<String> firstNames =
      await DataAccess.instance.getAColumnFrom<String, Person>('firstName');
  debugPrint('First names: $firstNames');

  // Project `firstName` for every female Person.
  // For boolean-typed columns you can use either `0` / `1` or `true` /
  // `false`: `true` maps to `1` and `false` maps to `0` (see `sex`).
  final List<String> womensfirstName = await DataAccess.instance
      .getAColumnFrom<String, Person>('firstName', afterWhere: 'sex = false');
  debugPrint('Women first names: $womensfirstName');

  // Project the first and last name of every Person.
  final List<Map<String, Object?>> firstNamesAndlastNames =
      await DataAccess.instance.getSommeColumnsFrom<Person>('firstName, lastName');
  debugPrint('First + last names: $firstNamesAndlastNames');

  // Project the first and last name of every female Person.
  final List<Map<String, Object?>> firstNamesAndlastNamesFemmes =
      await DataAccess.instance
          .getSommeColumnsFrom<Person>('firstName, lastName', afterWhere: 'sex = 0');
  debugPrint('Women first + last names: $firstNamesAndlastNamesFemmes');

  // Rename Birane (firstName=Birane, lastName=KEBE) to `developer` / `2022`.
  final bool witnessUpdatelastNameEtfirstName = await DataAccess.instance
      .updateSommeColumnsOf<Person>(
    <String>['firstName', 'lastName'],
    <String>['firstName', 'lastName'],
    <Object>['developer', '2022', 'Birane', 'KEBE'],
  );
  debugPrint('Update ok? $witnessUpdatelastNameEtfirstName');

  // Delete every Person whose `firstName` equals `Fatou`.
  final bool witnessDelFatou = await DataAccess.instance
      .deleteObjet<Person>("firstName = 'Fatou'");
  debugPrint('Fatou deleted? $witnessDelFatou');

  // Count the total number of Person rows.
  final int nbPerson = await DataAccess.instance.countElementsOf<Person>();
  debugPrint('Total rows: $nbPerson');

  // Count the number of male Person rows.
  final int nbMen = await DataAccess.instance
      .countElementsOf<Person>(afterWhere: 'sex = true');
  debugPrint('Male rows: $nbMen');

  /* Important!
     1. Most methods that query an entity's table throw
        `DatabaseException('no such table: ...')` when the table does not
        exist yet. The exceptions are `updateWholeObject`,
        `updateSommeColumnsOf`, `getAColumnFromWithTableName` and
        `getAColumnFrom`: these catch the error internally and log it via
        `debugPrint` to help debugging. For every other method, wrap the
        call in `try` / `catch` (or use `.catchError`) if you are not sure
        the table already exists, and react accordingly.
     2. Wrap your entity's `toMap()` call with
        `mapToUse(Map<String, dynamic> map, {bool forDB = true})` when
        needed: `mapToUse(entity.toMap(), forDB: false)` returns a plain
        `Map<String, dynamic>` suitable for non-SQLite use (e.g. JSON or
        UI display). The default `mapToUse(entity.toMap())` is what the
        package itself uses in `insertObjet` and `insertObjetList` to
        push entity data into the matching table. */

  /////////// DiscData.instance /////////////

  // Path to the directory that stores SQLite database files.
  final String databases = await DiscData.instance.databasesPath;
  debugPrint('Databases path: $databases');

  // Path to the default directory where user files are saved.
  final String files = await DiscData.instance.filesPath;
  debugPrint('Files path: $files');

  // Path to the application documents directory (the root used above).
  final String appFlutter = await DiscData.instance.rootPath;
  debugPrint('Root path: $appFlutter');

  // Save a text file into the default `files` directory.
  final String? fileName = await DiscData.instance.saveDataToDisc(
    'contents of test.txt',
    DataType.text,
    takeThisName: 'test.txt',
  );
  debugPrint('Saved file name: $fileName');

  // Check whether `test.txt` already exists on disk.
  final bool witnessTestFileExiste =
      await DiscData.instance.checkFileExists(fileName: 'test.txt');
  debugPrint('test.txt exists? $witnessTestFileExiste');

  // Read `test.txt` back as a UTF-8 string.
  final String? readTest =
      await DiscData.instance.readFileAsString(fileName: 'test.txt');
  debugPrint('test.txt content: $readTest');

  // Read `my_image.png` as a Base64-encoded string.
  final String? readTestAsBase64 =
      await DiscData.instance.readFileAsBase64(fileName: 'my_image.png');
  debugPrint('Base64 length: ${readTestAsBase64?.length ?? 0}');

  // Read `my_image.png` as raw bytes (Uint8List).
  final Uint8List? readTestBytes =
      await DiscData.instance.readFileAsBytes(fileName: 'my_image.png');
  debugPrint('Bytes length: ${readTestBytes?.length ?? 0}');

  // Read `my_image.png` and wrap it into a Flutter `Image` widget.
  final Image? readTestImage =
      await DiscData.instance.getImageFromDisc(imageName: 'my_image.png');
  debugPrint('Image loaded? ${readTestImage != null}');

  // Load a file whose name is stored in an SQLite table column.
  // Assume a table `Images` with a column `imageName` that holds the
  // file name of an image (e.g. `image_test.jpg`). The call below loads
  // the bytes of the file referenced by the row where `imageID = 1`.
  final Uint8List? readTestImageAsBytes = await DiscData.instance
      .getEntityFileOnDisc<Uint8List, Images>('imageName', 'imageID', 1);
  debugPrint('Entity file bytes: ${readTestImageAsBytes?.length ?? 0}');

  runApp(const MaterialApp(
    home: Scaffold(body: Center(child: Text('b012_data'))),
  ));
}

class Images {
  String? id;
  String? imageName;
  DateTime? dateSave;
  DateTime? dateLastUpdate;

  // Primary key declaration (required).
  MapEntry<String, bool> get pKeyAuto => const MapEntry('id', false);

  // Non-nullable columns (optional).
  List<String> get notNulls =>
      const <String>['imageName', 'dateSave', 'dateLastUpdate'];

  // Unnamed constructor used by the generic getters (required).
  Images([this.id, this.imageName, this.dateSave, this.dateLastUpdate]);

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id ?? ColumnType.String,
        'imageName': imageName ?? ColumnType.String,
        'dateSave': dateSave ?? ColumnType.DateTime,
        'dateLastUpdate': dateLastUpdate ?? ColumnType.DateTime,
      };

  Images.fromMap(Map<String, Object?> json, {bool isInt = true}) {
    id = json['id'] as String?;
    imageName = json['imageName'] as String?;
    dateSave = dateTime(json['dateSave'] as String?);
    dateLastUpdate = dateTime(json['dateLastUpdate'] as String?);
  }

  Images fromMap(Map<String, Object?> json) => Images.fromMap(json);
}
