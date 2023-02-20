library b012_data;

import 'dart:async';
import 'dart:math';

import 'package:b012_data/b012_disc_data.dart';
import 'package:flutter/cupertino.dart';
import 'package:sqflite/sqflite.dart';

class DataAccess {
  static final DataAccess instance = DataAccess._privateNamedConstructor();
  DataAccess._privateNamedConstructor();
  static Database? _db;

  Future<Database> get db async {
    return _db ??= await openDatabase(
        await DiscData.instance.readFileAsString(
                path: '${await DiscData.instance.databasesPath}/dbName') ??
            'sqlf_easy.db',
        version: 1);
  }

  /*
      Directory documentDirectory = await getApplicationDocumentsDirectory();
      path = join(documentDirectory.path, "ersen.db");
      resultat: path=/data/user/0/sn.prose.ersen.ersen/app_flutter/ersen.db
    Or
      String databasesPath = await getDatabasesPath();
      path = join(databasesPath, "ersen.db")  donne le meme path que si on passe directement le nom de la base a la methode openDatabase
      - resultat: path=/data/user/0/sn.prose.ersen.ersen/databases/ersen.db
      - real path from Device manager:/data/data/sn.prose.ersen.ersen/databases/ersen.db
      print("path======>$path");
  */
  Future<Database> openDB(String dbPath) async => await openDatabase(dbPath);

  Future<void> dropDB(String dbPath) async => await deleteDatabase(dbPath);

  ///Use for changing the default sqflite database (sqlf_easy.db) to a database of your preference<br/>
  ///Or simply switch beetween your existing databases.<br/>
  ///* if newDBName exists already it will be opened and becomes app's database util next change<br/>
  ///* If not then it will be created and opened as app's database util next change<br/>
  Future<void> changeDB(String? newDBName) async {
    if (newDBName != null && newDBName.isNotEmpty) {
      String newDBNameCorrectName =
          newDBName += newDBName.endsWith('.db') ? '' : '.db';
      String? dbName = await DiscData.instance.saveDataToDisc(
          newDBNameCorrectName, DataType.text,
          path: "${await DiscData.instance.databasesPath}/dbName");
      if (dbName != null) {
        await _db!.close();
        _db = await openDatabase(newDBNameCorrectName, version: 1);
        debugPrint("\n\nDatabase changed with success !\n\n");
      }
    } else
      debugPrint("\n\nYou provide a null or empty sting !\n\n");
  }

  ///This methode allow to save an objet to your sqflite db<br/>
  ///Exemple:<br/>
  ///bool witness=await insertObjet(Person('Mr','developper'));<br/>
  ///where Person is an existing entity.<br/>
  ///It can return false in two situations:<br/>
  ///1 . the object was null<br/>
  ///2 . insertion not succed due to somme column change or missing
  Future<bool> insertObjet(var object) async {
    int witness = 0;
    if (object != null) {
      Database database = (await db);
      await createTableIfNotExists(object);
      await database.transaction((txn) async {
        await txn
            .insert(object.runtimeType.toString(), mapToUse(object.toMap()))
            .then((value) {
          witness = value;
        }).catchError((_) {});
      });
    }
    return witness > 0;
  }

  ///This methode allow to save an entity's objet list to your sqflite db<br/>
  ///Exemple:<br/>
  ///bool witness=await insertObjetList([Person('Mr','developper'),Person('Mme','developper')]);<br/>
  ///where Person is an existing entity<br/>
  ///It can return false in two situations:<br/>
  ///1 . the objectlist was null or empty<br/>
  ///2 . insertions not succed due to somme column change or missing
  Future<bool> insertObjetList(List? objectlist) async {
    bool witness = false;
    if (objectlist != null && objectlist.isNotEmpty) {
      Database database = (await db);
      String table = objectlist.first.runtimeType.toString();
      await createTableIfNotExists(objectlist.first);
      await database.transaction((txn) async {
        for (var object in objectlist) {
          if (object != null) {
            await txn.insert(table, mapToUse(object.toMap())).then((value) {
              witness = value > 0;
            }).catchError((_) {
              witness = false;
            });
            if (!witness) break;
          }
        }
      });
    }
    return witness;
  }

  ///Remplace true or false in afterWhere string respectively by 1 or 0.
  String _clearAfterWhereFromBoolsAndDateTime(String afterWhere) {
    return afterWhere
        .replaceAll(RegExp(r"\s*=\s*true"), " = 1") //turn true to 1
        .replaceAll(RegExp(r"\s*=\s*false"), " = 0") //turn false to 0
        .replaceAllMapped(
            RegExp(
                r"\s*=\s*\d{4}(-\d{2}){2}([ :]\d{2}){3}[.]?\d{0,6}"), //turn dateTime to string for database.
            (Match m) => " = '${m.group(0)?.split('=').last.trim()}'");
  }

  ///For user login validate<br/><br/>
  ///Example:<br/>
  ///Account account=await DataAccess.instance.getLogin<Account>(Account(),'email',email,'passWord',passWord);
  ///Where email and passWord are the login information of the user that wants to log in.<br/><br/>
  ///This methode can throw no such table Error. <br/>
  ///Consider using catchErr or onError methods if you are not sure that the entity table already exists to handle this error when affecting.<br/>
  Future<T?> getLogin<T>(
      var tableEntityInstance,
      String identifierColumnName,
      String identifierValue,
      String passWordColumnName,
      String passWordValue) async {
    List<Map<String, Object?>> res;
    Database database = (await db);
    res = await database.transaction((txn) async {
      return await txn.rawQuery(
          "SELECT * FROM ${T.toString()} WHERE $identifierColumnName = '$identifierValue' and $passWordColumnName = '$passWordValue'");
    });

    if (res.isNotEmpty) return tableEntityInstance.fromMap(res.first);
    return null;
  }

  ///Returns a specific objet of type T (T=one of your entities) or null if that object do not existe.<br/><br/>
  ///This methode can throw no such table Error. <br/>
  ///Consider using catchErr or onError methods if you are not sure that the entity table already exists to handle this error when affecting.<br/>
  Future<T?> get<T>(var tableEntityInstance, String afterWhere) async {
    List<Map<String, Object?>> res;
    Database database = (await db);
    res = await database.transaction((txn) async {
      return await txn.rawQuery(
          "SELECT * FROM ${T.toString()} WHERE ${_clearAfterWhereFromBoolsAndDateTime(afterWhere)}");
    });

    if (res.isNotEmpty) return tableEntityInstance.fromMap(res.first);
    return null;
  }

  //returns a specific objet of type T (T=one of your entities) or null if that object do not existe
  /*Future<T> getObject<T>(String afterWhere) async {
    var res;
    var database = await this.db;
    await database.transaction((txn) async {
      res = await txn.rawQuery("SELECT * FROM ${T.toString()} WHERE $afterWhere");
    });

    if (res.length > 0)
      return allClassMap[T.toString()].fromMap(res.first);

    return null;
  }*/

  ///Returns all objects of type T stored on db. (T=one of your entities) or null if there are no object of type T present on database<br/><br/>
  ///This methode can throw no such table Error. <br/>
  ///Consider using catchErr or onError methods if you are not sure that the entity table already exists to handle this error when affecting.<br/>
  Future<List<T>?> getAll<T>(var tableEntityInstance) async {
    List<Map<String, Object?>> res;
    Database database = (await db);
    res = await database.transaction((txn) async {
      return await txn.query(T.toString());
    });

    if (res.isNotEmpty)
      return res.map((c) => tableEntityInstance.fromMap(c) as T).toList();
    return null;
  }

  ///Returns all objects of type T that satify the afterWhere condition (T=one of your entities) or null if no object is find were stored in database<br/><br/>
  ///This methode can throw no such table Error. <br/>
  ///Consider using catchErr or onError methods if you are not sure that the entity table already exists to handle this error when affecting.<br/>
  Future<List<T>?> getAllSorted<T>(
      var tableEntityInstance, String afterWhere) async {
    List<Map<String, Object?>> res;
    Database database = (await db);
    res = await database.transaction((txn) async {
      return await txn.rawQuery(
          "SELECT * FROM ${T.toString()} WHERE ${_clearAfterWhereFromBoolsAndDateTime(afterWhere)}");
    });

    if (res.isNotEmpty)
      return res.map((c) => tableEntityInstance.fromMap(c) as T).toList();
    return null;
  }

  ///Returns a column of type (C)  from an entity of type (T)<br/><br/>
  ///Example1 : <br/>
  ///List<String> firstNames=await DataAccess.instance.getAColumnFrom<String,Person>("firstName");<br/><br/>
  ///Example2 : <br/>
  ///List<Uint8List> fileContent=await DataAccess.instance.getAColumnFrom<Uint8List,Fichier>("content",afterWhere: "idEntity='1'  LIMIT 1")
  Future<List<C>> getAColumnFrom<C, T>(String columnName,
      {String? afterWhere}) async {
    List<C> dataList = [];
    await getSommeColumnsFrom<T>(columnName, afterWhere: afterWhere)
        .then((resultat) {
      dataList = resultat.map((line) => line[columnName] as C).toList();
    }).catchError((error) {
      debugPrint("\n\n${error.toString()}\n\n");
    });
    return dataList;
  }

  ///An other version of getAColumnFrom method that take the name of the entity table as parameter.<br/>
  ///This method is use when we prefer to provide the table or tables name as parameter or for<br/>
  ///quering none entity tables like sqlite_master.<br/>
  ///As an exemple this method is used by method like cleanAllTablesData() which<br/>
  ///use sqfite system table named sqlite_master to find all tables names of the used database.<br/>
  ///and drop theire data.<br/><br/>
  ///This method can also be use for getting a column from join tables. For that, table will be take names <br/>
  ///of different tables concern by the operation [[with their alias]] separated by comma.<br/>
  ///Exemeple :<br/>
  ///List<String> customNames=await getAColumnFromWithTableName<String>('c.name','Custom c, Profil p', afterWhere:"c.profil=p.id and p.name='faithful'")
  Future<List<T>> getAColumnFromWithTableName<T>(
      String columnName, String table,
      {String? afterWhere}) async {
    List<T> dataList = [];
    await getSommeColumnsWithTableName(columnName, table,
            afterWhere: afterWhere)
        .then((resultat) {
      dataList = resultat.map((line) => line[columnName] as T).toList();
    }).catchError((error) {
      debugPrint("\n\n${error.toString()}\n\n");
    });
    return dataList;
  }

  ///Can return any query result as List<Map<String, Object>> where every map is row from the selected table<br/>
  ///Exemple:<br/>
  ///List<Map<String, Object>> result = await getSommeColumnsFrom<Person>("firstName, lastName",afterWhere:"id=1");<br/><br/>
  ///This methode can throw no such table Error. <br/>
  ///Consider using catchErr or onError methods if you are not sure that the entity table already exists to handle this error when affecting.<br/>
  Future<List<Map<String, Object?>>> getSommeColumnsFrom<T>(
      String listDesColonne,
      {String? afterWhere}) async {
    List<Map<String, Object?>> res;
    Database database = (await db);
    res = await database.transaction((txn) async {
      return (await txn.rawQuery(
          "SELECT $listDesColonne FROM ${T.toString()} ${afterWhere != null ? 'WHERE ${_clearAfterWhereFromBoolsAndDateTime(afterWhere)}' : ''}"));
    });
    return res;
  }

  ///This method is use when we prefer to provide the table name as
  ///parameter or for quering none entity tables like sqlite_master.<br/>
  ///It returns any query result as List<Map<String, Object>> where every map is row from the selected table or tables if
  ///it's a jointure.<br/><br/>
  ///Example:<br/>
  ///List<Map<String, Object>> result = await getSommeColumnsWithTableName("firstName, lastName","Person",afterWhere: "id=1");<br/><br/>
  ///This methode can throw no such table Error. <br/>
  ///Consider using catchErr or onError methods if you are not sure that the table already exists to handle this error when affecting.<br/>
  Future<List<Map<String, Object?>>> getSommeColumnsWithTableName(
      String listDesColonne, String table,
      {String? afterWhere}) async {
    List<Map<String, Object?>> res;
    Database database = (await db);
    res = await database.transaction((txn) async {
      return (await txn.rawQuery(
          "SELECT $listDesColonne FROM $table ${afterWhere != null ? 'WHERE ${_clearAfterWhereFromBoolsAndDateTime(afterWhere)}' : ''}"));
    });
    return res; //Toutes les lignes verifiant le critaire
  }

  ///create an entity table if not exists.
  Future<void> createTableIfNotExists(var entity) async {
    if (!await checkIfTableExists(entity.runtimeType.toString())) {
      Database database = (await db);
      await database.transaction((txn) async {
        txn.execute(showCreateTable(entity));
      });
    }
  }

  ///returns the create table statement of the given object.
  String showCreateTable(var entity) {
    MapEntry<String, bool>? pKeyAuto;
    List<String>? notNulls;
    List<String>? uniques;
    Map<String, String>? checks;
    Map<String, String>? defaults;
    Map<String, List<String>>? fKeys;

    try {
      pKeyAuto = entity.pKeyAuto;
    } catch (e) {
      pKeyAuto = null;
    }
    try {
      notNulls = entity.notNulls;
    } catch (e) {
      notNulls = null;
    }
    try {
      uniques = entity.uniques;
    } catch (e) {
      uniques = null;
    }
    try {
      checks = entity.checks;
    } catch (e) {
      checks = null;
    }
    try {
      defaults = entity.defaults;
    } catch (e) {
      defaults = null;
    }
    try {
      fKeys = entity.fKeys;
    } catch (e) {
      fKeys = null;
    }

    StringBuffer createTableStatement = StringBuffer();
    createTableStatement
        .write('CREATE TABLE ${entity.runtimeType.toString()} (\n');
    Map<String, dynamic> objetToMap = entity.toMap();
    String objectLastFieldName = objetToMap.keys.last;
    bool hasForeignKey = fKeys != null;

    String columnType;
    objetToMap.forEach((columnName, columnValue) {
      //columnValue.runtimeType.toString() is a value in ['String','int','double','bool','DateTime','Uint8List']
      // if columnValue is not null. But, if it's null then columnValue's type must be ColumnType, so columnValue.toString().split('.').last
      // is in ['String','int','double','bool','DateTime','Uint8List'].
      //If no default ColumnType was and columnValue is null then the generated type of this fied will be TEXT.

      if (columnValue != null)
        columnType = columnValue is! ColumnType
            ? columnValue.runtimeType.toString()
            : columnValue.toString().split('.').last;
      else
        columnType = 'String';

      if (columnType == 'bool') {
        checks ??= {};
        checks![columnName] = '$columnName in (0,1)';
      }

      createTableStatement.write(_writeTableColumn(
          columnName,
          columnType == 'String'
              ? 'TEXT'
              : (columnType == 'int' || columnType == 'bool')
                  ? 'INTEGER'
                  : columnType == 'double'
                      ? 'REAL'
                      : columnType == 'DateTime'
                          ? 'DATETIME'
                          : 'BLOB',
          pKeyAuto,
          notNulls,
          uniques,
          checks,
          defaults,
          objectLastFieldName,
          hasForeignKey));
    });

    if (hasForeignKey) {
      String lastFKeyField = fKeys.keys.last;
      fKeys.forEach((fkField, refEntityAndField) {
        createTableStatement.write(
            "FOREIGN KEY($fkField) REFERENCES ${refEntityAndField.first}(${refEntityAndField[1]})${fkField != lastFKeyField ? ',\n' : '\n)'}");
      });
    }
    debugPrint("\n\n" + createTableStatement.toString());
    return createTableStatement.toString();
  }

  ///Allow us to get the list of column name's of an entity table store in sqlite.<br/>
  ///It is us to controlle if new column was added or deleted and ALTER the<br/>
  ///corresponding entiity table for adding or deleting that column.
  Future<List<String>> getEntityColumnsName<T>() async {
    Database database = await db;
    List<Map<String, Object?>> res;
    List<String> columnName = List.empty();
    await database.transaction((txn) async {
      res = await txn.rawQuery(
          "SELECT SQL FROM sqlite_master WHERE type='table' AND name='${T.toString()}'");
      if (res.isNotEmpty) {
        List<String> columnName = (res.first['sql'] as String).split('\n');
        columnName = columnName
            .sublist(1, columnName.length - 1)
            .map((colName) => colName.split(' ').first)
            .toList();
        columnName.removeWhere((element) => element == 'FOREIGN');
      }
    });
    return columnName;
  }

  ///returns a table column string base on getter that were define on your entities
  String _writeTableColumn(
      String columnName,
      String columnType,
      MapEntry<String, bool>? pKeyAuto,
      List<String>? notNulls,
      List<String>? uniques,
      Map<String, String>? checks,
      Map<String, String>? defaults,
      String objectLastFieldName,
      bool haveForeignKey) {
    StringBuffer tableColumn = StringBuffer();
    tableColumn.write("$columnName $columnType");

    if (pKeyAuto != null && pKeyAuto.key == columnName) {
      tableColumn.write(" PRIMARY KEY");
      if (pKeyAuto.value) tableColumn.write(" AUTOINCREMENT");
    }

    if (notNulls != null && notNulls.contains(columnName))
      tableColumn.write(" NOT NULL");

    if (uniques != null && uniques.contains(columnName))
      tableColumn.write(" UNIQUE");

    if (defaults != null && defaults.containsKey(columnName))
      tableColumn.write(" DEFAULT ${defaults[columnName]}");

    if (checks != null && checks.containsKey(columnName))
      tableColumn.write(" CHECK(${checks[columnName]})");

    tableColumn.write(
        columnName != objectLastFieldName || haveForeignKey ? ",\n" : "\n)");
    return tableColumn.toString();
  }

  ///check if table already exists.
  Future<bool> checkIfTableExists(String table) async {
    List<Map<String, Object?>> res;
    Database database = await db;
    res = await database.transaction((txn) async {
      return await txn.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='$table'");
    });

    if (res.isNotEmpty) return true;

    return false;
  }

  ///check if entity table already exists.
  Future<bool> checkIfEntityTableExists<T>() async {
    List<Map<String, Object?>> res;
    Database database = await db;
    res = await database.transaction((txn) async {
      return await txn.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='${T.toString()}'");
    });

    if (res.isNotEmpty) return true;

    return false;
  }

  ///Drop an entity table form the sqlite database.
  Future<void> dropTable<T>() async {
    Database database = await db;
    await database.transaction((txn) async {
      await txn.execute("DROP TABLE IF EXISTS ${T.toString()}");
    });
  }

/*  Future<void> _modifyATableStructure(
      String tableName, String createTableString) async {
    Database database = await db;
    await database.transaction((txn) async {
      txn.execute("PRAGMA writable_schema = 1");
      txn.execute(
          "UPDATE sqlite_master SET SQL = '$createTableString' WHERE NAME = '$tableName'");
      txn.execute("PRAGMA writable_schema = 0");
    });
  }*/

  /*-----------------------------------For update-------------------------------------------------*/
  ///Use for updating one or many fied of an  entity (T) table<br/>
  ///- The order or columns and their values must be respected<br/>
  ///* Example:<br/>
  ///    Using rawUpdate directely:<br/>
  ///      int count = await database.rawUpdate('UPDATE Test SET salaire = ?, ismaried=?, year = ? WHERE name = ?',[9000000,true, 45, 'Alpha']);<br/>
  ///    With updateSommeColumnsOf<T> method:<br/>
  ///      bool response=await updateSommeColumnsOf<Personn>(['salaire','ismaried','year'],['name'],[1000,true, 45, 'Alpha'])<br/>
  ///* whereMcop = whereMutliConditionOperation. This variable is use if there are many conditions to ckeck, its default value is ' and '.<br/>
  ///Its values are in [['and','or','in','not in','exits','not exits']] etc.
  Future<bool> updateSommeColumnsOf<T>(List<String> columnsToUpadate,
      List<String> whereColumns, List<Object> values,
      {String whereMcop = "and"}) async {
    int witness = 0;
    Database database = await db;
    await database.transaction((txn) async {
      await txn
          .rawUpdate(
              'UPDATE ${T.toString()} SET ${_preparedColumns(columnsToUpadate, ',')} WHERE ${_preparedColumns(whereColumns, whereMcop)}',
              _checkForBoolAndDateTime(values))
          .then((value) {
        witness = value;
      }).catchError((error) {
        debugPrint("\n\n${error.toString()}\n\n");
      });
    });
    return witness > 0;
  }

  /// Update all fieds of an entity object except the primary key<br/>
  ///- The order or columns and their values must be respected<br/>
  ///- int response = await updateWholeObject(Person(18,'M2Sir'),[["name"]],[["Alpha"]])<br/>
  ///* whereMcop = whereMutliConditionOperation. This variable is use if there are many conditions to ckeck, its default value is ' and '.<br/>
  ///Its values are in ['and','or','in','not in','exits','not exits']
  Future<bool> updateWholeObject(
      var newObject, List<String> whereColumns, List<Object> values,
      {String whereMcop = "and"}) async {
    Database database = await db;
    int witness = 0;
    await database.transaction((txn) async {
      await txn
          .update(newObject.runtimeType.toString(), mapToUse(newObject.toMap()),
              where: _preparedColumns(whereColumns, whereMcop),
              whereArgs: _checkForBoolAndDateTime(values))
          .then((value) {
        witness = value;
      }).catchError((error) {
        debugPrint("\n\n${error.toString()}\n\n");
      });
    });
    return witness > 0;
  }

  ///Check for sqlite no supported type (boolean, DateTime) and correct them to be accepted.<br/>
  ///Boolean values are convert to a value of {0,1}, DateTimes are convert to String for update operations.
  List<Object> _checkForBoolAndDateTime(List<Object> values) {
    return values.map((columnValue) {
      if (columnValue is bool)
        return columnValue ? 1 : 0;
      else if (columnValue is DateTime) return columnValue.toString();
      return columnValue;
    }).toList();
  }

  ///Returns a prepared string of a list of columns for sql query. whereMcop = where Mutlicondition Operation
  String _preparedColumns(List<String> whereColumns, String whereMcop) {
    return whereColumns
        .map((whereColumn) => "$whereColumn= ?")
        .join(' $whereMcop ');
  }

  ///Example:<br/>
  ///bool witness=await deleteObjet<Test>([['email','passWord']],[['test@gmail.com','passer']])<br/><br/>
  ///This methode can throw no such table Error. <br/>
  ///Consider using catchErr or onError methods if you are not sure that the entity table already exists to handle this error when affecting.<br/>
  Future<bool> delObjet<T>(List<String> whereColumns, List<Object> whereArgs,
      {String whereMcop = "and"}) async {
    int res;
    Database database = await db;
    res = await database.transaction((txn) async {
      return await txn.delete(T.toString(),
          where: _preparedColumns(whereColumns, whereMcop),
          whereArgs: whereArgs);
    });
    return res > 0;
  }

  ///delete and object(s) on database base on afterWhere<br/>
  ///bool witness=await deleteObjet<Fichier>("id=1");
  ///Warning!!!. If afterWhere is null then the table will be truncated.<br/><br/>
  ///This methode can throw no such table Error. <br/>
  ///Consider using catchErr or onError methods if you are not sure that the entity table already exists to handle this error when affecting.<br/>
  Future<bool> deleteObjet<T>([String? afterWhere]) async {
    int res;
    Database database = await db;
    res = await database.transaction((txn) async {
      return await txn.rawDelete(
          "DELETE FROM ${T.toString()} ${afterWhere != null ? "WHERE ${_clearAfterWhereFromBoolsAndDateTime(afterWhere)}" : ""}");
    });
    return res > 0;
  }

  /// Counts the number of elements of type T or depending to expression and afterWhere condition.<br/>
  /// - expression = [['*' ou 'DISTINCT | ALL Expression']]<br/>
  /// Example: expression ='distinct name.<br/><br/>
  ///This methode can throw no such table Error. <br/>
  ///Consider using catchErr or onError methods if you are not sure that the table already exists to handle this error when affecting.<br/>
  Future<int> countElementsOf<T>(
      {String expression = '*', String? afterWhere}) async {
    List<Map<String, Object?>> res;
    Database database = await db;
    res = await database.transaction((txn) async {
      return await txn.rawQuery(
          "SELECT count($expression) FROM ${T.toString()}${afterWhere != null ? " WHERE ${_clearAfterWhereFromBoolsAndDateTime(afterWhere)}" : ""}");
    });
    return Sqflite.firstIntValue(res)!;
  }

  Future<void> cleanAllTablesData() async {
    await DataAccess.instance.db.then((value) async {
      await DataAccess.instance
          .getAColumnFromWithTableName<String>('name', 'sqlite_master',
              afterWhere: "type='table'")
          .then((tables) async {
        await value.transaction((txn) async {
          for (String table in tables) await txn.execute("DELETE FROM $table");
        });
      });
    });
  }
}

///Use when we want to convert an entity to a map for database insertion or is it like a normal Map in our code.<br/>
///By default, forDB is set to true because the method is use by the package for inserting enties data.<br/>
///into their corresponding tables. <br/><br/>
///Set, forDB to false if it's not for database insertion.
Map<String, dynamic> mapToUse(Map<String, dynamic> objetToMap,
    {bool forDB = true}) {
  return objetToMap.map((key, value) {
    if (value is ColumnType)
      return MapEntry(key, null);
    else if (value is bool && forDB)
      return MapEntry(key, value ? 1 : 0);
    else if (value is DateTime && forDB) return MapEntry(key, value.toString());

    return MapEntry(key, value);
  });
}

extension ExtraUsefullFunctionExtension on String {
  String get spacedNumbers => this.replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]} ');
}

///
Iterable<int> range(int lenOrStart, [int? end]) {
  int tmp;
  if (end != null && end < lenOrStart) {
    tmp = end;
    end = lenOrStart;
    lenOrStart = tmp;
  }
  return end == null
      ? Iterable.generate(lenOrStart, (index) => index)
      : Iterable.generate(end - lenOrStart, (index) => lenOrStart++);
}

///getter than returns a key of 32 random characters of numerics,majuscules and minuscules
String get newKey {
  Random rng = Random();
  String numericsAndChars =
      "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
  StringBuffer key = StringBuffer();
  for (int i = 0; i < 32; i++) key.write(numericsAndChars[rng.nextInt(62)]);
  return key.toString();
}

///Dart's primitive types. User at the moment that the package create an entity's table on sqlite database.<br/>
///It's use when never the corresponding the correspondinf field is null to determine the type of the column
enum ColumnType { int, double, String, bool, DateTime, Uint8List }

////prend [(1 ou 0) ou (true ou false)] et return respectivement [(true ou false) ou (1 ou 0)]
dynamic boolean(var intOrBool, {bool isInt = true}) {
  if (intOrBool != null) return isInt ? intOrBool > 0 : intOrBool;
  return null;
}

///permet de convertir une date (String) issu de la base de donnees sqflite en DateTime
DateTime? dateTime(String? dateString) =>
    dateString != null ? DateTime.parse(dateString) : null;
