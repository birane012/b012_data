import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:path_provider/path_provider.dart';
class DiscData {
  static final DiscData instance=DiscData._privateNamedConstructor();
  DiscData._privateNamedConstructor(){appPath;}
  String filesPath;
  String databasesPath;
  String rootPath;

  Future<String> get appPath async {
    rootPath = (await getApplicationDocumentsDirectory()).path;
    filesPath="${getParentDir(rootPath)}/files";
    databasesPath="${getParentDir(rootPath)}/databases";
    return rootPath;
  }

  ///If path (entire Lunix or windows path) is provide, fileName must be null<br/>
  bool checkFileExists(String fileName,{String path})=>File(validatePath(path)??"$filesPath/$fileName").existsSync();

  ///get reduce url path by one directory.<br/>
  ///Exampe: <br/>
  /// if path = "/flutter/app/dir/test"<br/>
  /// getParentDir(path) returns "/flutter/app/dir"
  String getParentDir(String path)=>(path.split('/')..removeLast()).join('/');

  ///Use for saving data to a specific path on disc<br/>
  ///* If path is not provid data will be save in the application directory name files.<br/>
  ///* If path (entire Lunix or windows path) is provide, fileName must be null<br/>
  ///* If DataType (type of the data we want to save) equals DataType.text it will be saved as text file<br/>
  /// else it is saved as binary file (e.g for image, audio,pdf,video etc.)<br/>
  ///* About recursive:<br/>
  ///  Calling saveDataToDisc on an existing file on given path or name might fail if there are restrictive permissions on the file<br/>
  ///  If recursive is false, the default, the file is created only if all directories in its path already exist.<br/>
  ///  If recursive is true, all non-existing parent paths are created first.<br/>
  ///  Throws a FileSystemException if the operation fails.<br/><br/>
  ///* returns the name of the file or  null if null or empty data was given
  String saveDataToDisc(var data,DataType dataType,{String takeThisName,String path,bool recursive=false}) {
    if(data!=null && data.isNotEmpty) {
      String fileName;
      if(path!=null)
        fileName=path.split("/").last;
      else
        fileName=takeThisName??DateTime.now().toString();

      File fileToSave = File(validatePath(path) ?? "$filesPath/$fileName");
      fileToSave.createSync(recursive: recursive);

      switch(dataType){
        case DataType.text:
          fileToSave.writeAsStringSync(data);
          break;
        case DataType.base64:
        case DataType.bytes:
          if(dataType==DataType.base64)
            data = base64Decode(data);
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
  void appendDataToFile(var data,DataType dataType,String fileName,{String path}) {
    File fileToSave = File(validatePath(path)??"$filesPath/$fileName");
    if(data!=null && data.isNotEmpty && fileToSave.existsSync()) {
      switch(dataType){
        case DataType.text:
          fileToSave.writeAsStringSync(data,mode: FileMode.append);
          break;
        case DataType.base64:
        case DataType.bytes:
          if(dataType==DataType.base64)
            data = base64Decode(data);
          fileToSave.writeAsBytesSync(data,mode: FileMode.append);
          break;
      }
    }
  }

  ///Check if the given path is correct.<br/>
  ///If the path wasn't correct it will correct it and return a god one<br/>
  ///* returns null if null or empty path was given
  String validatePath(String path){
    if(path!=null && path.isNotEmpty){
      StringBuffer validPath=StringBuffer();
      int len=path.length;

      if(!path.startsWith('/')) {
        validPath.write("/");
        len++;
      }

      if(path.endsWith('/') || path.endsWith('\\'))
        validPath.write(path.substring(0,len-2));
      else
        validPath.write(path);
      return validPath.toString().replaceAll("\\", "/").replaceAll("//", "/").replaceAll('\\\\', '/');
    }

    return null;
  }

  ///if path (entire Lunix or windows path) is provide, fileName must be null<br/>
  ///* returns file as base64 string or null if file do not exists
  String readFileAsBase64(String fileName,{String path}){
    File file = File(validatePath(path)??"$filesPath/$fileName");
    if(file.existsSync())
      return base64Encode(File(validatePath(path)??"$filesPath/$fileName").readAsBytesSync());
    return null;
  }

  ///if path (entire Lunix or windows path) is provide, fileName must be null<br/>
  ///* returns file as bytes (Uint8List) or null if file do not exists
  Uint8List readFileAsBytes(String fileName,{String path}){
    File file = File(validatePath(path)??"$filesPath/$fileName");
    if(file.existsSync())
      return file.readAsBytesSync();
    return null;
  }

  ///if path (entire Lunix or windows path) is provide, fileName must be null<br/>
  ///* returns the text store in file or null if file do not exists
  String readFileAsString(String fileName,{String path}){
    File file = File(validatePath(path)??"$filesPath/$fileName");
    if(file.existsSync())
      return file.readAsStringSync();
    return null;
  }

  ///if path (entire Lunix or windows path) is provide, fileName must be null.<br/>
  ///* returns the file or null if file do not exists
  File getFile(String fileName,{String path}){
    File file = File(validatePath(path)??"$filesPath/$fileName");
    if(file.existsSync())
      return file;
    return null;
  }

  ///* returns the Image or null if image do not exist
  Image getImageFromDisc(String imageName, {String path,BoxFit fit=BoxFit.fill}) {
    if(imageName==null || imageName.isEmpty)
      return null;
    return Image.memory(DiscData.instance.readFileAsBytes(imageName,path: path), fit: fit);
  }
}

enum DataType{
  text,
  base64,
  bytes
}