import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:path_provider/path_provider.dart';
import 'package:b012_data/b012_sqlflite_easy.dart';

class DiscData {
  static final DiscData instance = DiscData._privateNamedConstructor();
  DiscData._privateNamedConstructor();
  String? _rootPath;
  String? _databasesPath;
  String? _filesPath;
  String _pathJoin = !Platform.isWindows ? '/' : '\\';

  ///Returns the default directory name where files saved without precise path are stored.<br/>
  ///In Windows it's C:\Users\userName. User have access to this directory without using the app<br/>
  ///So to avoid that he delete some data we make it a hidden directory (.files)
  String _defaultFilesDirectory = !Platform.isWindows ? 'files' : '.files';

  Future<String> get rootPath async =>
      _rootPath ?? (await getApplicationDocumentsDirectory()).path;

  Future<String> get databasesPath async =>
      _databasesPath ?? "${getParentDir(await rootPath)}${_pathJoin}databases";

  Future<String> get filesPath async =>
      _filesPath ??
      "${getParentDir(await rootPath)}$_pathJoin$_defaultFilesDirectory";

  Future<bool> checkFileExists({String? fileName, String? path}) async =>
      File(validatePath(path) ?? "${await filesPath}$_pathJoin$fileName")
          .existsSync();

  ///get reduce url path by one directory.<br/>
  ///Exampe: <br/>
  /// if path = "/flutter/app/dir/test"<br/>
  /// getParentDir(path) returns "/flutter/app/dir"
  String getParentDir(String path) =>
      (path.split(_pathJoin)..removeLast()).join(_pathJoin);

  ///Use for saving data to a specific path on disc<br/>
  ///* If path is not provid data will be saved in the application directory name files.<br/>
  ///* If path (entire Lunix or windows path) is provide data will be saved in that specific path.<br/>
  ///* If DataType (type of the data we want to save) equals DataType.text it will be saved as text file<br/>
  /// else it is saved as binary file (e.g for image, audio,pdf,video etc.)<br/>
  ///* About recursive:<br/>
  ///  Calling saveDataToDisc on an existing file on given path or name might fail if there are restrictive permissions on the file<br/>
  ///  If recursive is false, the default, the file is created only if all directories in its path already exist.<br/>
  ///  If recursive is true, all non-existing parent paths are created first.<br/>
  ///  Throws a FileSystemException if the operation fails.<br/><br/>
  ///* returns the name of the file or  null if null or empty data was given
  Future<String?> saveDataToDisc(var data, DataType dataType,
      {String? takeThisName, String? path, bool recursive = false}) async {
    if (data != null && data.isNotEmpty) {
      String fileName;
      if (path != null)
        fileName = path.split(_pathJoin).last;
      else
        fileName = takeThisName ?? DateTime.now().toString();

      if (Platform.isWindows) fileName = fileName.replaceAll(':', '');

      File fileToSave =
          File(validatePath(path) ?? "${await filesPath}$_pathJoin$fileName");
      fileToSave.createSync(recursive: recursive);
      switch (dataType) {
        case DataType.text:
          fileToSave.writeAsStringSync(data);
          break;
        case DataType.base64:
        case DataType.bytes:
          if (dataType == DataType.base64) data = base64Decode(data);
          fileToSave.writeAsBytesSync(data);
          break;
      }
      return fileName;
    }
    return null;
  }

  ///Use for app append data to a specific file on disc.<br/>
  ///* If path is not provid it will seach the file in the application directory named files.<br/>
  ///* If path (entire Lunix or windows path) is provide, fileName must be null<br/>
  ///* If DataType (type of the data we want to save) equals DataType.text it will append the given string to the text file<br/>
  /// else it appends the data as bytes to the file<br/>
  Future<void> appendDataToFile(var data, DataType dataType,
      {String? fileName, String? path}) async {
    File fileToSave =
        File(validatePath(path) ?? "${await filesPath}$_pathJoin$fileName");
    if (data != null && data.isNotEmpty && fileToSave.existsSync()) {
      switch (dataType) {
        case DataType.text:
          fileToSave.writeAsStringSync(data, mode: FileMode.append);
          break;
        case DataType.base64:
        case DataType.bytes:
          if (dataType == DataType.base64) data = base64Decode(data);
          fileToSave.writeAsBytesSync(data, mode: FileMode.append);
          break;
      }
    }
  }

  ///Check if the given path is correct.<br/>
  ///If the path wasn't correct it will correct it and return a god one<br/>
  ///* returns null if null or empty path was given
  String? validatePath(String? path) {
    if (path != null && path.isNotEmpty) {
      StringBuffer validPath = StringBuffer();
      int len = path.length;

      if (!path.startsWith('/') && !Platform.isWindows) {
        validPath.write("/");
        len++;
      }

      if (path.endsWith('/') || path.endsWith('\\'))
        validPath.write(path.substring(0, len - 2));
      else
        validPath.write(path);

      return validPath.toString().replaceAll(RegExp(r"[/\\]+"), _pathJoin);
    }

    return null;
  }

  ///if path (entire Lunix or windows path) is provide, fileName must be null<br/>
  ///* returns file as base64 string or null if file do not exists
  Future<String?> readFileAsBase64({String? fileName, String? path}) async {
    File file =
        File(validatePath(path) ?? "${await filesPath}$_pathJoin$fileName");
    return file.existsSync()
        ? base64Encode(
            File(validatePath(path) ?? "${await filesPath}$_pathJoin$fileName")
                .readAsBytesSync())
        : null;
  }

  ///if path (entire Lunix or windows path) is provide, fileName must be null<br/>
  ///* returns file as bytes (Uint8List) or null if file do not exists
  Future<Uint8List?> readFileAsBytes({String? fileName, String? path}) async {
    File file =
        File(validatePath(path) ?? "${await filesPath}$_pathJoin$fileName");
    return file.existsSync() ? file.readAsBytesSync() : null;
  }

  ///if path (entire Lunix or windows path) is provide, fileName must be null<br/>
  ///* returns the text store in file or null if file do not exists<br/>
  Future<String?> readFileAsString({String? fileName, String? path}) async {
    File file =
        File(validatePath(path) ?? "${await filesPath}$_pathJoin$fileName");
    return file.existsSync() ? file.readAsStringSync() : null;
  }

  ///if path (entire Lunix or windows path) is provide, fileName must be null.<br/>
  ///* returns the file or null if file do not exists
  Future<File?> getFile({String? fileName, String? path}) async {
    File file =
        File(validatePath(path) ?? "${await filesPath}$_pathJoin$fileName");
    return file.existsSync() ? file : null;
  }

  Future<bool> deleteFile({String? fileName, String? path}) async {
    File file =
        File(validatePath(path) ?? "${await filesPath}$_pathJoin$fileName");
    if (file.existsSync()) file.deleteSync();
    return !file.existsSync();
  }

  ///* returns the Image or null if image do not exist.
  ///It takes imageName if image is in files directory or the the entire path of the image.
  Future<Image?> getImageFromDisc(
      {String? imageName, String? path, BoxFit fit = BoxFit.fill}) async {
    if (imageName == null || imageName.isEmpty) return null;
    return Image.memory(
        (await DiscData.instance
            .readFileAsBytes(fileName: imageName, path: path))!,
        fit: fit);
  }

  ///It will take the url from T's table and get the file on path/fileName or the systePath/fileName<br/>
  ///D is the type of the loaded data (Unit8List, String, integer, etc)
  Future<D?> getEntityFileOnDisc<D, T>(
      String urlColumnName, String key, dynamic value,
      {String? path}) async {
    var urls = await DataAccess.instance.getAColumnFrom<String, T>(
        urlColumnName,
        afterWhere: "$key='$value' LIMIT 1");
    if (urls.isEmpty) return null;

    if (D == Uint8List)
      return path != null
          ? await DiscData.instance
              .readFileAsBytes(path: "$path$_pathJoin${urls.first}") as D
          : await DiscData.instance.readFileAsBytes(fileName: urls.first) as D;
    else
      return path != null
          ? await DiscData.instance
              .readFileAsString(path: "$path$_pathJoin${urls.first}") as D
          : await DiscData.instance.readFileAsString(fileName: urls.first) as D;
  }
}

///Check if internet connection is available.
Future<bool> get isInternetAvailable async {
  bool status = true;
  await InternetAddress.lookup('google.com').onError((error, stackTrace) {
    if (error is SocketException) status = false;
    return []; //This is for the onError method. Because the body might complete normally, causing 'null' to be returned,
    // but the return type, 'FutureOr<List<InternetAddress>>', is a potentially non-nullable type.
  });
  return status;
}

enum DataType { text, base64, bytes }
