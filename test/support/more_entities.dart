import 'package:b012_data/b012_sqlflite_easy.dart';

/// A document whose file name is stored in [url].
class Doc {
  Doc([this.id, this.title, this.url]);

  Doc.fromMap(Map<String, Object?> json)
    : id = json['id'] as String?,
      title = json['title'] as String?,
      url = json['url'] as String?;

  String? id;
  String? title;
  String? url;

  MapEntry<String, bool> get pKeyAuto => const MapEntry('id', false);

  Map<String, dynamic> toMap() => <String, dynamic>{
    'id': id ?? ColumnType.String,
    'title': title ?? ColumnType.String,
    'url': url ?? ColumnType.String,
  };

  Doc fromMap(Map<String, Object?> json) => Doc.fromMap(json);
}

/// An entity whose class and column names are SQL keywords.
class Order {
  Order([this.id, this.group, this.order]);

  Order.fromMap(Map<String, Object?> json)
    : id = json['id'] as int?,
      group = json['group'] as String?,
      order = json['order'] as int?;

  int? id;
  String? group;
  int? order;

  MapEntry<String, bool> get pKeyAuto => const MapEntry('id', true);

  Map<String, dynamic> toMap() => <String, dynamic>{
    'id': id ?? ColumnType.int,
    'group': group ?? ColumnType.String,
    'order': order ?? ColumnType.int,
  };

  Order fromMap(Map<String, Object?> json) => Order.fromMap(json);
}

/// Constant `checks` together with a boolean column.
class Flag {
  Flag([this.id, this.on, this.label]);

  Flag.fromMap(Map<String, Object?> json)
    : id = json['id'] as int?,
      on = boolean(json['on']) as bool?,
      label = json['label'] as String?;

  int? id;
  bool? on;
  String? label;

  MapEntry<String, bool> get pKeyAuto => const MapEntry('id', true);

  Map<String, String> get checks => const <String, String>{
    'label': 'length(label) > 0',
  };

  Map<String, dynamic> toMap() => <String, dynamic>{
    'id': id ?? ColumnType.int,
    'on': on ?? ColumnType.bool,
    'label': label ?? ColumnType.String,
  };

  Flag fromMap(Map<String, Object?> json) => Flag.fromMap(json);
}

/// An entity whose `notNulls` getter throws.
class Broken {
  Broken([this.id, this.name]);

  Broken.fromMap(Map<String, Object?> json)
    : id = json['id'] as int?,
      name = json['name'] as String?;

  int? id;
  String? name;

  List<String> get notNulls => throw StateError('broken getter');

  Map<String, dynamic> toMap() => <String, dynamic>{
    'id': id ?? ColumnType.int,
    'name': name ?? ColumnType.String,
  };

  Broken fromMap(Map<String, Object?> json) => Broken.fromMap(json);
}
