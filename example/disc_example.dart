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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // File system / binary file walk-through (Images entity).
  await runDiscDemo();

  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('runDiscDemo tests completed'))),
    ),
  );
}
