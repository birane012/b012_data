# b012_data is for data manipulations. It provide 

## NB: <br/>
    Package name: B012_data
    **Regles:**<br/>
    - Define a constructor with optional argument that holds every fied<br/>.
        Example: Business([this.idBusiness,this.nomBusiness,this.dateCreation,this.siege,this.isChoose])

    - field names of type date must containt the substring *date*. Nb: this substring is not cas sensitive<br/>
        Examples: dateCreation,creationDate,creationDATE,theDaTeOf

    - field names of type Uint8List must containt the substring *file*. Nb: this substring is not cas sensitive<br/>
        Examples: fileName,fileContent,imageFILE,profilFile

    - Add constraints using optionaly these 5 getter depending on what constraint you woud add:<br/>
        Example:<br/>
        CREATE TABLE Business (
          idBusiness text PRIMARY KEY,
          nomBusiness text NOT NULL,
          dateCreation Datetime NOT NULL,
          siege text DEFAULT NULL,
          isChoose INTEGER NOT NULL CHECK(isChoose IN (0,1))
        )
        is geneate as follow:<br/>

        String get pKey => "idBusiness";
        List<String> get notNulls => <String>['nomBusiness','dateCreation','isChoose'];
        List<String> get uniques => null;
        Map<String,String> get checks => {'isChoose':'isChoose in (0,1)'};
        Map<String,String> get defaults => {'siege':'NULL'};
        Map<String,List<String>> get fKeys => {'siege':['Siege','idSiege']};

        If a constraint is not need,you don't have to set its corresponding getter or simply make it return null<br/>

    - Always define a named constructor and an inatance method with the same name fromMap like below:<br/>
        Entite.fromMap(dynamic jsonOrMap) and <br/>
        Entite fromMap(dynamic jsonOrMap)=>Entite.fromMap(jsonOrMap)<br/>

    - Define the Map<String, dynamic> toMap() methode and make sure to assign an aproprate default value to each null ones

    ///////////////////////////////////////////////  ABOUT SQLITE  ////////////////////////////////////////////////////////
    - Important note from sqlite documentation:<br/>
        Supported SQLite types<br/>
        No validity check is done on values yet so please avoid non supported types https://www.sqlite.org/datatype3.html<br/>
        DateTime is not a supported SQLite type. Personally I store them as int (millisSinceEpoch) or string (iso8601).<br/> 
        SQLite TIMESTAMP type sometimes requires using date functions. TIMESTAMP values are read as String that the application needs to parse.<br/>
        
        bool is not a supported SQLite type. Use INTEGER and 0 and 1 values.

        Whwen tying to save data type bool, it fails and the below message appears
        *** WARNING ***
        I/flutter (26142): Invalid argument true with type bool.
        I/flutter (26142): Only num, String and Uint8List are supported. See https://github.com/tekartik/sqflite/blob/master/sqflite/doc/supported_types.md for details
        I/flutter (26142): This will throw an exception in the future. For now it is displayed once per type.

        
        INTEGER
        * SQLite type: INTEGER
        * Dart type: int
        * Supported values: from -2^63 to 2^63 - 1
        
        REAL
        * SQLite type: REAL
        * Dart type: num
        
        TEXT
        * SQLite type: TEXT
        * Dart type: String
        
        BLOB
        * SQLite typ: BLOB
        * Dart type: Uint8List
