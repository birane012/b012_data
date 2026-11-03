import 'package:b012_data/b012_sqlflite_easy.dart';

/// The entity of the package example.
class Person {
  Person([
    this.idPers,
    this.firstName,
    this.lastName,
    this.sex,
    this.dateOfBirth,
  ]);

  Person.fromMap(Map<String, Object?> json, {bool isInt = true}) {
    idPers = json['idPers'] as String?;
    firstName = json['firstName'] as String?;
    lastName = json['lastName'] as String?;
    sex = boolean(json['sex'], isInt: isInt) as bool?;
    dateOfBirth = dateTime(json['dateOfBirth'] as String?);
  }

  String? idPers;
  String? firstName;
  String? lastName;
  bool? sex;
  DateTime? dateOfBirth;

  MapEntry<String, bool> get pKeyAuto => const MapEntry('idPers', false);

  List<String> get notNulls => const <String>[
    'firstName',
    'lastName',
    'sex',
    'dateOfBirth',
  ];

  Map<String, dynamic> toMap() => <String, dynamic>{
    'idPers': idPers ?? ColumnType.String,
    'firstName': firstName ?? ColumnType.String,
    'lastName': lastName ?? ColumnType.String,
    'sex': sex ?? ColumnType.bool,
    'dateOfBirth': dateOfBirth ?? ColumnType.DateTime,
  };

  Person fromMap(Map<String, Object?> json) => Person.fromMap(json);
}

/// An entity with an auto-incremented key, a unique column and a default.
class Account {
  Account([this.id, this.email, this.password, this.credit]);

  Account.fromMap(Map<String, Object?> json)
    : id = json['id'] as int?,
      email = json['email'] as String?,
      password = json['password'] as String?,
      credit = json['credit'] as double?;

  int? id;
  String? email;
  String? password;
  double? credit;

  MapEntry<String, bool> get pKeyAuto => const MapEntry('id', true);

  List<String> get uniques => const <String>['email'];

  Map<String, String> get defaults => const <String, String>{'credit': '0'};

  Map<String, dynamic> toMap() => <String, dynamic>{
    'id': id ?? ColumnType.int,
    'email': email ?? ColumnType.String,
    'password': password ?? ColumnType.String,
    'credit': credit ?? ColumnType.double,
  };

  Account fromMap(Map<String, Object?> json) => Account.fromMap(json);
}
