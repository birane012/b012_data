library b012_data;

import 'dart:async';
import 'dart:math';

import 'package:b012_data/b012_disc_data.dart';
import 'package:sqflite/sqflite.dart';

class DataAccess {
  static final DataAccess instance=DataAccess._privateNamedConstructor();
  DataAccess._privateNamedConstructor();
  static Database _db;

  Future<Database> get db async {
    _db??=await openDatabase(await DiscData.instance.readFileAsString(null,path: '${await DiscData.instance.databasesPath}/dbName')??'sqlf_easy.db',version: 1);
    return _db;
  }

  /*Directory documentDirectory = await getApplicationDocumentsDirectory();
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
  Future<void> changeDB(String newDBName) async {
    if(newDBName!=null && newDBName.isNotEmpty){
      String newDBNameCorrectName=newDBName+=newDBName.endsWith('.db')?'':'.db';
      String dbName=await DiscData.instance.saveDataToDisc(newDBNameCorrectName, DataType.text,path: "${await DiscData.instance.databasesPath}/dbName");
      if(dbName!=null) {
        await _db.close();
        _db=await openDatabase(newDBNameCorrectName,version: 1);
      }
    }
  }

  ///This methode allow to save an objet to your sqflite db<br/>
  ///Exemple:<br/>
  ///bool witness=await insertObjet(Person('Mr','developper'));<br/>
  ///where Person is an existing entity.<br/>
  ///It can return false in two situations:<br/>
  ///1 . the object was null<br/>
  ///2 . insertion not succed due to somme column change or missing
  Future<bool> insertObjet(var object) async {
    int witness=0;
    if(object!=null){
      Database database = await db;
      await createTableIfNotExists(object);
      await database.transaction((txn) async {
        await txn.insert(object.runtimeType.toString(),mapToUseForInsert(object.toMap())).then((value){witness=value;}).catchError((_){});
      });
    }
    return witness>0;
  }

  ///This methode allow to save an entity's objet list to your sqflite db<br/>
  ///Exemple:<br/>
  ///bool witness=await insertObjetList([Person('Mr','developper'),Person('Mme','developper')]);<br/>
  ///where Person is an existing entity<br/>
  ///It can return false in two situations:<br/>
  ///1 . the objectlist was null or empty<br/>
  ///2 . insertions not succed due to somme column change or missing
  Future<bool> insertObjetList(List objectlist) async {
    bool witness=false;
    if(objectlist!=null && objectlist.isNotEmpty){
      Database database = await db;
      String table = objectlist[0].runtimeType.toString();
      await createTableIfNotExists(objectlist[0]);
      await database.transaction((txn) async {
        for(var object in objectlist) {
          if(object!=null){
            await txn.insert(table,mapToUseForInsert(object.toMap())).then((value){witness=value>0;}).catchError((_){witness=false;});
            if(!witness)
              break;
          }
        }
      });
    }
    return witness;
  }

  Map<String,dynamic> mapToUseForInsert(Map<String,dynamic> objetToMap){
    return objetToMap.map((key, value){
      return value is ColumnType? MapEntry(key, null): MapEntry(key, value);
    });
  }

  ///For user login validate<br/><br/>
  ///Example:<br/>
  ///Account account=await DataAccess.instance.getLogin<Account>(Account(),'email',email,'passWord',passWord);<br/><br/>
  ///Where email and passWord are the login information of the user that wants to log in
  Future<T> getLogin<T>(var tableEntityInstance,String identifierColumnName,String identifierValue,String passWordColumnName,String passWordValue) async {
    List<Map<String, Object>> res;
    Database database = await db;
    await database.transaction((txn) async {
      res = await txn.rawQuery("SELECT * FROM ${T.toString()} WHERE $identifierColumnName = '$identifierValue' and $passWordColumnName = '$passWordValue'");
    });

    if(res.isNotEmpty)
      return tableEntityInstance.fromMap(res.first);
    return null;
  }

  ///returns a specific objet of type T (T=one of your entities) or null if that object do not existe
  Future<T> get<T>(var tableEntityInstance,String afterWhere) async {
    List<Map<String, Object>> res;
    Database database = await db;
    await database.transaction((txn) async {
      res = await txn.rawQuery("SELECT * FROM ${T.toString()} WHERE $afterWhere");
    });

    if(res.isNotEmpty)
      return tableEntityInstance.fromMap(res.first);
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

  ///returns all objects of type T stored on db. (T=one of your entities) or null if there are no object of type T present on database
  Future<List<T>> getAll<T>(var tableEntityInstance) async {
    List<Map<String, Object>> res;
    Database database = await db;
    await database.transaction((txn) async {
      res = await txn.query(T.toString());
    });

    if(res.isNotEmpty)
      return res.map((c) =>tableEntityInstance.fromMap(c) as T).toList();
    return null;
  }

  ///returns all objects of type T that satify the afterWhere condition (T=one of your entities) or null if no object is find were stored in database
  Future<List<T>> getAllSorted<T>(var tableEntityInstance,String afterWhere) async {
    List<Map<String, Object>> res;
    Database database = await db;
    await database.transaction((txn) async {
      res = await txn.rawQuery("SELECT * FROM ${T.toString()} WHERE $afterWhere");
    });

    if(res.isNotEmpty)
      return res.map((c) => tableEntityInstance.fromMap(c) as T).toList();
    return null;
  }

  ///Returns a column of type (C)  from an entity of type (T)<br/><br/>
  ///Example1 : <br/>
  ///List<String> firstNames=await DataAccess.instance.getAColumnFrom<String,Personne>("firstName");<br/><br/>
  ///Example2 : <br/>
  ///List<Uint8List> fileContent=await DataAccess.instance.getAColumnFrom<Uint8List,Fichier>("content",afterWhere: "idEntity='1'  LIMIT 1")
  Future<List<C>> getAColumnFrom<C,T>(String columnName,{String afterWhere}) async {
    List<C> dataList=[];
    await getSommeColumnsFrom<T>(columnName,afterWhere: afterWhere).then((resultat) {
      dataList=resultat.map((line) => line[columnName] as C).toList();
    }).catchError((_){});
    return dataList;
  }

  ///Can return any query result as List<Map<String, Object>> where every map is row from the selected table<br/>
  ///Exemple:<br/>
  ///getSommeColumnsFrom("prenom, nom","Personne","usertype","fourniseur");
  Future<List<Map<String, Object>>> getSommeColumnsFrom<T>(String listDesColonne, {String afterWhere}) async {
    List<Map<String, Object>> res;
    Database database = await db;
    await database.transaction((txn) async {
      res = await txn.rawQuery("SELECT $listDesColonne FROM ${T.toString()} ${afterWhere!=null? 'WHERE $afterWhere':''}");
    });
    return res;
  }

  ///create an entity table if not exists.
  Future<void> createTableIfNotExists(var entity)  async {
    if(!await checkIfTableExists(entity.runtimeType.toString())){
      Database database = await db;
      await database.transaction((txn) async{txn.execute(showCreateTable(entity));});
    }
  }

  ///returns the create table statement of the given object.
  String showCreateTable(var entity) {
    MapEntry<String,bool> pKeyAuto;
    List<String> notNulls;
    List<String> uniques;
    Map<String,String> checks;
    Map<String,String> defaults;
    Map<String,List<String>> fKeys;

    try {pKeyAuto=entity.pKeyAuto;} catch(e){pKeyAuto=null;}
    try {notNulls=entity.notNulls;} catch(e){notNulls=null;}
    try {uniques=entity.uniques;} catch(e){uniques=null;}
    try {checks=entity.checks;} catch(e){checks=null;}
    try {defaults=entity.defaults;} catch(e){defaults=null;}
    try {fKeys=entity.fKeys;} catch(e){fKeys=null;}

    StringBuffer createTableStatement = StringBuffer();
    createTableStatement.write('CREATE TABLE ${entity.runtimeType.toString()} (\n');
    Map<String, dynamic> objetToMap=entity.toMap();
    String objectLastFieldName = objetToMap.keys.last;
    bool haveForeignKey = fKeys!=null;
    const List<String> primitiveTypes=<String>['String','int','double','bool','DateTime','Uint8List'];

    String columnType;
    String columnTypeIfNull;
    objetToMap.forEach((columnName,columnValue) {
      //columnTypeIfNull=columnValue.toString() OR a value of ['String','int','double','bool','DateTime','Uint8List']
      // if columnValue was null. In that case columnValue is a value of type ColumnType then
      // columnValue.toString().split('.').last will also return a value of ['String','int','double','bool','DateTime','Uint8List']
      columnTypeIfNull = columnValue.toString().split('.').last;
      if(primitiveTypes.contains(columnTypeIfNull))
        columnType=columnTypeIfNull;
      else
        columnType=columnValue.runtimeType.toString();

      switch(columnType){
        case 'String':
          createTableStatement.write(writeTableColumn(columnName,'TEXT',pKeyAuto,notNulls,uniques,checks,defaults,objectLastFieldName,haveForeignKey));
          break;
        case 'int':
          createTableStatement.write(writeTableColumn(columnName,'INTEGER',pKeyAuto,notNulls,uniques,checks,defaults,objectLastFieldName,haveForeignKey));
          break;
        case 'double':
          createTableStatement.write(writeTableColumn(columnName,'REAL',pKeyAuto,notNulls,uniques,checks,defaults,objectLastFieldName,haveForeignKey));
          break;
        case 'bool':
          checks ??= {};
          checks[columnName]='$columnName in (0,1)';
          createTableStatement.write(writeTableColumn(columnName,'INTEGER',pKeyAuto,notNulls,uniques,checks,defaults,objectLastFieldName,haveForeignKey));
          break;
        case 'DateTime':
          createTableStatement.write(writeTableColumn(columnName,'DATETIME',pKeyAuto,notNulls,uniques,checks,defaults,objectLastFieldName,haveForeignKey));
          break;
        case 'Uint8List':
          createTableStatement.write(writeTableColumn(columnName,'BLOB',pKeyAuto,notNulls,uniques,checks,defaults,objectLastFieldName,haveForeignKey));
          break;
        default:
          createTableStatement.write(writeTableColumn(columnName,'TEXT',pKeyAuto,notNulls,uniques,checks,defaults,objectLastFieldName,haveForeignKey));
      }
    });

    if(haveForeignKey){
      String lastFKeyField = fKeys.keys.last;
      fKeys.forEach((fkField, refEntityAndField) {
        createTableStatement.write("FOREIGN KEY($fkField) REFERENCES ${refEntityAndField[0]}(${refEntityAndField[1]})${fkField!=lastFKeyField? ',\n':'\n)'}");
      });
    }
    print("\n\n"+createTableStatement.toString());
    return createTableStatement.toString();
  }

  ///returns a table column string base on getter that were define on your entities
  String writeTableColumn(String columnName,String columnType,MapEntry<String,bool> pKeyAuto,List<String> notNulls,List<String> uniques,Map<String,String> checks,Map<String,String> defaults,String objectLastFieldName,bool haveForeignKey){
    StringBuffer tableColumn = StringBuffer();
    tableColumn.write("$columnName $columnType");

    if(pKeyAuto!=null && pKeyAuto.key==columnName) {
      tableColumn.write(" PRIMARY KEY");
      if(pKeyAuto.value)
        tableColumn.write(" AUTOINCREMENT");
    }

    if(notNulls!=null && notNulls.contains(columnName))
      tableColumn.write(" NOT NULL");

    if(uniques!=null && uniques.contains(columnName))
      tableColumn.write(" UNIQUE");

    if(defaults!=null && defaults.containsKey(columnName))
      tableColumn.write(" DEFAULT ${defaults[columnName]}");

    if(checks!=null && checks.containsKey(columnName))
      tableColumn.write(" CHECK(${checks[columnName]})");

    tableColumn.write(columnName!=objectLastFieldName||haveForeignKey? ",\n":"\n)");
    return tableColumn.toString();
  }

  ///check if table already exists.
  Future<bool> checkIfTableExists(String table) async {
    List<Map<String, Object>> res;
    Database database = await db;
    await database.transaction((txn) async {
      res = await txn.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='$table'");
    });

    if(res.isNotEmpty)
      return true;

    return false;
  }

  ///check if entity table already exists.
  Future<bool> checkIfEntityTableExists<T>() async {
    List<Map<String, Object>> res;
    Database database = await db;
    await database.transaction((txn) async {
      res = await txn.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='${T.toString()}'");
    });

    if(res.isNotEmpty)
      return true;

    return false;
  }

  Future<void> dropTable<T>() async {
    Database database = await db;
    await database.transaction((txn) async {
      await txn.execute("DROP TABLE IF EXISTS ${T.toString()}");
    });
  }

  Future<void> modifyATableStructure(String tableName, String createTableString) async {
    Database database = await db;
    await database.transaction((txn) async {
      txn.execute("PRAGMA writable_schema = 1");
      txn.execute("UPDATE sqlite_master SET SQL = '$createTableString' WHERE NAME = '$tableName'");
      txn.execute("PRAGMA writable_schema = 0");
    });
  }

  /*-----------------------------------For update-------------------------------------------------*/
  ///Use for updating one or many fied or an entity (T) table<br/>
  ///- The order or columns and their values must be respected<br/>
  ///* Example:<br/>
  ///    Using rawUpdate directely:<br/>
  ///      int count = await database.rawUpdate('UPDATE Test SET salaire = ?, ismaried=?, year = ? WHERE name = ?',[9000000,true, 45, 'Alpha']);<br/>
  ///    With updateSommeColumnsOf<T> method:<br/>
  ///      bool response=await updateSommeColumnsOf<Personn>(['salaire','ismaried','year'],['name'],[1000,true, 45, 'Alpha'])<br/>
  ///* whereMcop = whereMutliConditionOperation. This variable is use if there are many conditions to ckeck, its default value is ' and '.<br/>
  ///Its values are in [['and','or','in','not in','exits','not exits']] etc.
  Future<bool> updateSommeColumnsOf<T>(List<String> columnsToUpadate,List<String> whereColumns,List<Object> values,{String whereMcop="and"}) async {
    StringBuffer columnsToUpadateString = StringBuffer();
    for (String column in columnsToUpadate){
      columnsToUpadateString.write(column!=columnsToUpadate.last? "$column = ?, ":"$column = ? ");
    }

    int temoin;
    Database database = await db;
    await database.transaction((txn) async {
      temoin=await txn.rawUpdate('UPDATE ${T.toString()} SET ${columnsToUpadateString.toString()} WHERE ${getWhereString(whereColumns,whereMcop)}',values);
    });
    return temoin>0;
  }

  /// Update all fieds of an entity object except the primary key<br/>
  ///- The order or columns and their values must be respected<br/>  ///- int response = await updateWholeObject(Person(18,'M2Sir'),[["name"]],[["Alpha"]])<br/>
  ///* whereMcop = whereMutliConditionOperation. This variable is use if there are many conditions to ckeck, its default value is ' and '.<br/>
  ///Its values are in ['and','or','in','not in','exits','not exits']
  Future<bool> updateWholeObject(var newObject,List<String> whereColumns,List<Object> values,{String whereMcop="and"}) async {
    Database database = await db;
    int witness;
    await database.transaction((txn) async {
      witness= await txn.update(newObject.runtimeType.toString(), newObject.toMap(),where: getWhereString(whereColumns,whereMcop),whereArgs: values);
    });
    return witness>0;
  }

  ///returns an after where statement from a list of whereColumns and whereMcop (whereMutliConditionOperation)
  String getWhereString(List<String> whereColumns,String whereMcop){
    StringBuffer whereString = StringBuffer();
    for (String whereColumn in whereColumns) {
      if(whereColumn!=whereColumns.last)
        whereString.write(whereColumn!=null? "$whereColumn = ? $whereMcop ": "$whereColumn is null $whereMcop");
      else
        whereString.write(whereColumn!=null? "$whereColumn = ? ": "$whereColumn is null");
    }
    return whereString.toString();
  }

  ///Example:<br/>
  ///bool witness=await deleteObjet<Test>([['email','passWord']],[['test@gmail.com','passer']])
  Future<bool> delObjet<T>(List<String> whereColumns,List<Object> whereArgs,{String whereMcop="and"}) async {
    int res;
    Database database = await db;
    await database.transaction((txn) async {
      res = await txn.delete(T.toString(), where: getWhereString(whereColumns,whereMcop), whereArgs: whereArgs);
    });
    return res>0;
  }

  ///delete and object(s) on database base on afterWhere<br/>
  ///bool witness=await deleteObjet<Fichier>("id=1");
  Future<bool> deleteObjet<T>(String afterWhere) async {
    int res;
    Database database = await db;
    await database.transaction((txn) async {
      res = await txn.rawDelete("DELETE FROM ${T.toString()} WHERE $afterWhere");
    });
    return res>0;
  }

  /// Counts the number of elements of type T or depending to expression and afterWhere condition.<br/>
  /// - expression = [['*' ou 'DISTINCT | ALL Expression']]<br/>
  /// Example: expression ='distinct nom'
  Future<int> countElementsOf<T>({String expression='*',String afterWhere}) async {
    //for(int i in .range())
    List<Map<String, Object>> res;
    Database database = await db;
    await database.transaction((txn) async {
      res = await txn.rawQuery("SELECT count($expression) FROM ${T.toString()}${afterWhere!=null? " WHERE $afterWhere":""}");
    });
    return Sqflite.firstIntValue(res);
  }
}

extension StringNumberExtension on String {
  String get spacedNumbers=>this.replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]} ');
}

///
List<int> range(int lenOrStart,[int end]){
  int tmp;
  /* for(int i in Iterable.generate(10))
      print("====>$i");*/
  if(end!=null && end<lenOrStart){
    tmp=end;
    end=lenOrStart;
    lenOrStart=tmp;
  }
  return end==null? List.generate(lenOrStart,(index) => index) : List.generate(end-lenOrStart, (index) => lenOrStart++);
}


///getter than returns a key of 32 random characters of numerics,majuscules and minuscules
String get newKey{
  Random rng = Random();
  String numericsAndChars="0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
  StringBuffer key=StringBuffer();
  for(int i=0;i<32;i++)
    key.write(numericsAndChars[rng.nextInt(62)]);
  return key.toString();
}

enum ColumnType {
  int,
  double,
  String,
  bool,
  DateTime,
  Uint8List
}

   //A faire pour rendre possible l'utlisation des booleen avec sqlite ameliorer le package
/* us cas of boolean method in fromMap we shoud have:
  Business.fromMap(dynamic jsonOrMap,{bool intToBool=true}){
  idBusiness=jsonOrMap["idBusiness"];
  nomBusiness=jsonOrMap["nomBusiness"];
  dateCreation=jsonOrMap["dateCreation"];
  siege=jsonOrMap["siege"];
  isChoose=boolean(jsonOrMap["isChoose"],intToBool:intToBool);
  }*/

/*  us cas of mapToUseForInsert method we shoud have:
  Map<String,dynamic> mapToUseForInsert(Map<String,dynamic> objetToMap){
    return objetToMap.map((key, value){
      if(value is ColumnType)
        return MapEntry(key, null);
      else if(value is bool)
        return MapEntry(key,value?1:0);

      return MapEntry(key, value);
    });
  }*/