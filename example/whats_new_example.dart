// What is new in b012_data 2.1: stable table names, bound values,
// transactions, paged queries, replace, raw SQL. Run alone with
// `flutter run -t example/whats_new_example.dart`.
import 'package:b012_data/b012_sqlflite_easy.dart';
import 'package:flutter/material.dart';

import 'sqlite_example.dart' show Person;

Future<void> runWhatsNewDemo() async {
  final DataAccess da = DataAccess.instance;

  // A stable table name: obfuscated or web release builds rename classes.
  da.registerEntity<Person>('person');
  await da.createTableIfNotExists(Person());

  // Opt-in safety nets.
  da.onError = (Object e, StackTrace s) => debugPrint('b012_data: $e');

  // Bound values: user input never becomes SQL.
  const String typed = "O'Neil";
  final Person? oneil = await da.get<Person>(
    Person(),
    'lastName = ?',
    <Object?>[typed],
  );
  debugPrint('Found $typed? ${oneil != null}');

  // All or nothing.
  try {
    await da.transaction(() async {
      await da.insertObjet(
        Person(newKey, 'Awa', 'Diop', false, DateTime(1998, 2, 3)),
      );
      throw StateError('changed my mind');
    });
  } on StateError {
    debugPrint('Rolled back: Awa was not kept.');
  }

  // Insert or replace the row with the same key.
  final String id = newKey;
  await da.insertObjet(Person(id, 'Moussa', 'Ba', true, DateTime(1990)));
  await da.insertObjet(
    Person(id, 'Moussa', 'Ba-Diallo', true, DateTime(1990)),
    orReplace: true,
  );

  // Paged, bound query: [] when nothing matches.
  final List<Person> men = await da.query<Person>(
    Person(),
    where: 'sex = ?',
    whereArgs: <Object?>[true],
    orderBy: 'lastName',
    limit: 10,
  );
  debugPrint('Men, first page: ${men.map((Person p) => p.lastName)}');

  // Raw SQL, still bound.
  final List<Map<String, Object?>> born = await da.rawQuery(
    'SELECT count(*) AS n FROM person WHERE dateOfBirth >= ?',
    <Object?>[DateTime(1995)],
  );
  debugPrint('Born since 1995: ${born.single['n']}');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await runWhatsNewDemo();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('What is new in 2.1: done'))),
    ),
  );
}
