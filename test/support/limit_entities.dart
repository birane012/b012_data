import 'package:b012_data/b012_sqlflite_easy.dart';

/// A technician assigned to a maintenance, for one trade: composite key.
class Assignment {
  Assignment([this.maintenanceId, this.technicianId, this.trade]);

  Assignment.fromMap(Map<String, Object?> json)
    : maintenanceId = json['maintenanceId'] as String?,
      technicianId = json['technicianId'] as String?,
      trade = json['trade'] as String?;

  String? maintenanceId;
  String? technicianId;
  String? trade;

  List<String> get pKeys => const <String>['maintenanceId', 'technicianId'];

  Map<String, List<String>> get indexes => const <String, List<String>>{
    'assignment_trade': <String>['trade'],
  };

  Map<String, List<String>> get uniqueIndexes => const <String, List<String>>{
    'assignment_one_trade': <String>['maintenanceId', 'trade'],
  };

  Map<String, dynamic> toMap() => <String, dynamic>{
    'maintenanceId': maintenanceId ?? ColumnType.String,
    'technicianId': technicianId ?? ColumnType.String,
    'trade': trade ?? ColumnType.String,
  };

  Assignment fromMap(Map<String, Object?> json) => Assignment.fromMap(json);
}

/// First version of a contact.
class ContactV1 {
  ContactV1([this.id, this.name]);

  ContactV1.fromMap(Map<String, Object?> json)
    : id = json['id'] as int?,
      name = json['name'] as String?;

  int? id;
  String? name;

  MapEntry<String, bool> get pKeyAuto => const MapEntry('id', true);

  Map<String, dynamic> toMap() => <String, dynamic>{
    'id': id ?? ColumnType.int,
    'name': name ?? ColumnType.String,
  };

  ContactV1 fromMap(Map<String, Object?> json) => ContactV1.fromMap(json);
}

/// Second version of the same contact: two new columns.
class ContactV2 {
  ContactV2([this.id, this.name, this.phone, this.active]);

  ContactV2.fromMap(Map<String, Object?> json)
    : id = json['id'] as int?,
      name = json['name'] as String?,
      phone = json['phone'] as String?,
      active = boolean(json['active']) as bool?;

  int? id;
  String? name;
  String? phone;
  bool? active;

  MapEntry<String, bool> get pKeyAuto => const MapEntry('id', true);

  List<String> get notNulls => const <String>['active'];

  Map<String, String> get defaults => const <String, String>{'active': '1'};

  Map<String, dynamic> toMap() => <String, dynamic>{
    'id': id ?? ColumnType.int,
    'name': name ?? ColumnType.String,
    'phone': phone ?? ColumnType.String,
    'active': active ?? ColumnType.bool,
  };

  ContactV2 fromMap(Map<String, Object?> json) => ContactV2.fromMap(json);
}

class Parent {
  Parent([this.id]);

  Parent.fromMap(Map<String, Object?> json) : id = json['id'] as int?;

  int? id;

  MapEntry<String, bool> get pKeyAuto => const MapEntry('id', false);

  Map<String, dynamic> toMap() => <String, dynamic>{'id': id ?? ColumnType.int};

  Parent fromMap(Map<String, Object?> json) => Parent.fromMap(json);
}

class Child {
  Child([this.id, this.parentId]);

  Child.fromMap(Map<String, Object?> json)
    : id = json['id'] as int?,
      parentId = json['parentId'] as int?;

  int? id;
  int? parentId;

  MapEntry<String, bool> get pKeyAuto => const MapEntry('id', true);

  Map<String, List<String>> get fKeys => const <String, List<String>>{
    'parentId': <String>['Parent', 'id'],
  };

  Map<String, dynamic> toMap() => <String, dynamic>{
    'id': id ?? ColumnType.int,
    'parentId': parentId ?? ColumnType.int,
  };

  Child fromMap(Map<String, Object?> json) => Child.fromMap(json);
}
