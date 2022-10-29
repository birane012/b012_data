import 'package:b012_data/b012_disc_data.dart';
import 'package:b012_data/b012_sqlflite_easy.dart';
import 'package:flutter/material.dart';

//Person Entity
class Person {
  String idPers;
  String firstName;
  String lastName;
  bool sex;
  DateTime dateOfBirth;

  //Step 1:
  MapEntry<String, bool> get pKeyAuto => const MapEntry('idPers', false);
  List<String> get notNulls =>
      <String>['firstName', 'lastName', 'sex', 'dateOfBirth'];

  //Step 2:
  Person(
      [this.idPers, this.firstName, this.lastName, this.sex, this.dateOfBirth]);

  //Step 3:
  Map<String, dynamic> toMap() => {
        "idPers": idPers ?? ColumnType.String,
        "firstName": firstName ?? ColumnType.String,
        "lastName": lastName ?? ColumnType.String,
        "sex": sex ?? ColumnType.bool,
        "dateOfBirth": dateOfBirth ?? ColumnType.DateTime,
      };

  //Step 4:
  Person.fromMap(dynamic jsonOrMap, {bool isInt = true}) {
    idPers = jsonOrMap["idPers"];
    firstName = jsonOrMap["firstName"];
    lastName = jsonOrMap["lastName"];
    sex = boolean(jsonOrMap["sex"], isInt: isInt);
    dateOfBirth = dateTime(jsonOrMap["dateOfBirth"]);
  }

  //Step 5:
  Person fromMap(dynamic jsonOrMap) => Person.fromMap(jsonOrMap);
}

//////////////////////////////////Exemple of use://////////////////////////////////

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  ///////////DataAccess.instance/////////////

  //Show create table query of Person entity
  DataAccess.instance.showCreateTable(Person());

  //Check if the Person table exists in the database
  bool witnessPersTableExiste =
      await DataAccess.instance.checkIfEntityTableExists<Person>();

  //Insert a new person in Person table
  bool tInsert = await DataAccess.instance.insertObjet(
      Person(newKey, 'KEBE', 'Birane', true, DateTime(1994, 03, 01)));

  //Insert a list of persons in Person table
  bool tInsertList = await DataAccess.instance.insertObjet(<Person>[
    Person(newKey, 'Mbaye', 'Aliou', true, DateTime(1999, 05, 01)),
    Person(newKey, 'Cisse', 'Fatou', false, DateTime(2000, 07, 09))
  ]);

  //Find a person
  Person birane = await DataAccess.instance
      .get<Person>(Person(), "firstName='Birane' and lastName='KEBE'");

  //Fing find all persons in Person table
  List<Person> Persons = await DataAccess.instance.getAll<Person>(Person());

  //Find men in Person table
  List<Person> hommes =
      await DataAccess.instance.getAllSorted<Person>(Person(), 'sex=1');

  //Collect all first names
  List<String> firstNames =
      await DataAccess.instance.getAColumnFrom<String, Person>('firstName');

  //Collect all first names of female persons
  List<String> firstNamesFemmes = await DataAccess.instance
      .getAColumnFrom<String, Person>('firstName', afterWhere: "sex=0");

  //Collect all first and last names of Persons
  List<Map<String, Object>> firstNamesAndlastNames = await DataAccess.instance
      .getSommeColumnsFrom<Person>("firstName,lastName");

  //Collect all first and last names of female persons
  List<Map<String, Object>> firstNamesAndlastNamesFemmes = await DataAccess
      .instance
      .getSommeColumnsFrom<Person>("firstName,lastName", afterWhere: "sex=0");

  //Change Birane's first name to developer and last name KEBE in 2022
  bool witnessUpdatelastNameEtfirstName = await DataAccess.instance
      .updateSommeColumnsOf<Person>(['firstName', 'lastName'],
          ['firstName', 'lastName'], ['developper', '2022', 'Birane', 'KEBE']);

  //delete a Person with firstName Fatou
  bool witnessDelFatou =
      await DataAccess.instance.deleteObjet<Person>("firstName='Fatou'");

  //Count the lastNumber of Persons
  int nbPerson = await DataAccess.instance.countElementsOf<Person>();

  //Counts the lastNumber of Male Person
  int nbMen =
      await DataAccess.instance.countElementsOf<Person>(afterWhere: 'sex=1');

  ///////////DataAccess.instance/////////////

  //databases path
  String databases = await DiscData.instance.databasesPath;

  //files path
  String files = await DiscData.instance.filesPath;

  //files path
  String appFlutter = await DiscData.instance.rootPath;

  //Save text data to disc on files directory
  String fileName = await DiscData.instance.saveDataToDisc(
      'contenu du fichier test.txt', DataType.text,
      takeThisName: 'test.txt');

  //Check if test.txt file exists
  bool witnessTestFileExiste =
      await DiscData.instance.checkFileExists('test.txt');

  //Read the contents of the test.txt file
  String readTest = await DiscData.instance.readFileAsString('test.txt');

  //A top level function that dumps all data from database tables.
  await cleanAllTablesData();

  runApp(Container());
}
