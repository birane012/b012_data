// Checks b012_data in a browser. Run:
//   cd tool/web_check && flutter pub get && dart run b012_data:setup_web
//   flutter run -d web-server --web-port 8013
// then open http://localhost:8013/?step=all&db=check1 and read the console
// line starting with B012_WEB_CHECK.
//
// Steps: all (every check), write (n rows, then leave the page at once),
// count (rows written so far), probe (one read: shows a lock error when the
// database is open in another tab), hold (opens the database and keeps it).
import 'dart:convert';
import 'dart:typed_data';

import 'package:b012_data/b012_disc_data.dart';
import 'package:b012_data/b012_sqlflite_easy.dart';
import 'package:flutter/material.dart';
import 'package:sqlite3/wasm.dart';
import 'package:web/web.dart' as web;

class Visit {
  Visit([this.id, this.site, this.done, this.when]);

  Visit.fromMap(Map<String, Object?> m)
    : id = m['id'] as String?,
      site = m['site'] as String?,
      done = boolean(m['done']) as bool?,
      when = dateTime(m['when'] as String?);

  String? id;
  String? site;
  bool? done;
  DateTime? when;

  MapEntry<String, bool> get pKeyAuto => const MapEntry('id', false);

  Map<String, List<String>> get indexes => const <String, List<String>>{
    'visit_site': <String>['site'],
  };

  Map<String, dynamic> toMap() => <String, dynamic>{
    'id': id ?? ColumnType.String,
    'site': site ?? ColumnType.String,
    'done': done ?? ColumnType.bool,
    'when': when ?? ColumnType.DateTime,
  };

  Visit fromMap(Map<String, Object?> m) => Visit.fromMap(m);
}

class Unregistered {
  Map<String, dynamic> toMap() => <String, dynamic>{'x': ColumnType.int};
}

final DataAccess da = DataAccess.instance;
final DiscData disc = DiscData.instance;

Future<Object?> attempt(Future<Object?> Function() body) async {
  try {
    return await body();
  } catch (e) {
    final String m = 'ERROR ${e.runtimeType}: $e';
    return m.length > 160 ? m.substring(0, 160) : m;
  }
}

Future<Map<String, Object?>> all() async {
  final Map<String, Object?> r = <String, Object?>{};
  final DateTime d = DateTime(2026, 11, 3, 9, 30);
  await da.insertObjetList(<Visit>[
    Visit('v1', 'Dakar', true, d),
    Visit('v2', 'Thiès', false, d.add(const Duration(days: 1))),
    Visit('v3', "Saint-Louis l'île", true, d.add(const Duration(days: 2))),
  ]);
  r['insert + count'] = await da.countElementsOf<Visit>() == 3;
  r['whereArgs date + bool'] =
      (await da.get<Visit>(Visit(), '"when" = ? AND done = ?', <Object?>[
        d,
        true,
      ]))?.id ==
      'v1';
  r['apostrophe bound'] =
      (await da.get<Visit>(Visit(), 'site = ?', <Object?>[
        "Saint-Louis l'île",
      ]))?.id ==
      'v3';
  r['query paging'] =
      (await da.query<Visit>(
        Visit(),
        orderBy: 'id DESC',
        limit: 1,
        offset: 1,
      )).single.id ==
      'v2';
  r['update'] = await da.updateSomeColumnsOf<Visit>(
    <String>['done'],
    <String>['id'],
    <Object>[true, 'v2'],
  );
  r['orReplace'] =
      await da.insertObjet(Visit('v2', 'Thiès', false, d), orReplace: true) &&
      (await da.getAColumnFrom<int, Visit>(
            'done',
            afterWhere: 'id = ?',
            whereArgs: <Object?>['v2'],
          )).join() ==
          '0';
  r['transaction rollback'] = await attempt(() async {
    try {
      await da.transaction(() async {
        await da.insertObjet(Visit('v9', 'X', true, d));
        if (d.year > 0) throw StateError('abandon');
      });
    } on StateError {
      return await da.countElementsOf<Visit>(
            afterWhere: 'id = ?',
            whereArgs: <Object?>['v9'],
          ) ==
          0;
    }
    return false;
  });
  r['delete'] = await da.delObjet<Visit>(<String>['id'], <Object>['v3']);
  r['index created'] =
      (await da.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index' AND name = ?",
        <Object?>['visit_site'],
      )).length ==
      1;
  r['migration ran'] =
      (await da.rawQuery('PRAGMA user_version')).single['user_version'] == 1;
  r['unregistered refused'] = await attempt(
    () async => (await attempt(
      () => da.insertObjet(Unregistered()),
    )).toString().contains('must be registered'),
  );
  r['db getter refused'] = (await attempt(
    () => da.db,
  )).toString().contains('not available in a browser');

  await disc.saveDataToDisc('bonjour', DataType.text, takeThisName: 'a.txt');
  await disc.appendDataToFile(' le monde', DataType.text, fileName: 'a.txt');
  r['files text'] =
      await disc.readFileAsString(fileName: 'a.txt') == 'bonjour le monde';
  r['files base64'] =
      await disc.readFileAsBase64(fileName: 'a.txt') ==
      base64Encode(utf8.encode('bonjour le monde'));
  r['files exists'] = await disc.checkFileExists(fileName: 'a.txt');
  r['files getFile null'] = await disc.getFile(fileName: 'a.txt') == null;
  r['files name escape refused'] = (await attempt(
    () => disc.saveDataToDisc('x', DataType.text, takeThisName: '../x.txt'),
  )).toString().contains('ArgumentError');
  final Uint8List png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
  );
  await disc.saveDataToDisc(png, DataType.bytes, takeThisName: 'p.png');
  r['files image'] = await disc.getImageFromDisc(imageName: 'p.png') != null;
  r['files delete'] =
      await disc.deleteFile(fileName: 'a.txt') &&
      !await disc.checkFileExists(fileName: 'a.txt');
  r['internet probe'] = await isInternetAvailable;
  r['close then reopen at once'] = await attempt(() async {
    await da.closeDB();
    return await da.countElementsOf<Visit>() == 2;
  });
  return r;
}

/// Reads the database straight from IndexedDB, through a second SQLite.
Future<Object?> independentCount(String db) async {
  final WasmSqlite3 s = await WasmSqlite3.loadFromUrl(
    Uri.parse('sqlite3mc.wasm'),
  );
  final IndexedDbFileSystem fs = await IndexedDbFileSystem.open(
    dbName: 'b012_data',
    vfsName: 'probe',
  );
  s.registerVirtualFileSystem(fs, makeDefault: false);
  final CommonDatabase d = s.open('/$db.db', vfs: 'probe');
  try {
    return d.select('SELECT count(*) AS n FROM visit').first['n'];
  } finally {
    d.close();
    await fs.close();
  }
}

Future<Map<String, Object?>> run(Map<String, String> q) async {
  da.registerEntity<Visit>('visit');
  da.migrations = <int, Future<void> Function()>{
    1: () => da.rawExecute('CREATE TABLE IF NOT EXISTS meta (k TEXT)'),
  };
  final String? wasm = q['wasm'];
  if (wasm != null) da.webSqliteWasmUri = Uri.parse(wasm);
  final String? key = q['key'];
  if (key != null) await da.useEncryptionKey(key);
  if (q['step'] == 'wait') {
    // Tries at once (the other tab holds the lock), waits, then retries
    // until the lock is free, and counts what the other tab wrote meanwhile.
    final Object? first = await attempt(
      () => da.changeDB(q['db']!).then((_) => 'opened'),
    );
    await Future<void>.delayed(const Duration(seconds: 15));
    for (int i = 0; i < 60; i++) {
      try {
        await da.changeDB(q['db']!);
        break;
      } on StateError {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    return <String, Object?>{
      'first attempt': first.toString().length > 60
          ? first.toString().substring(0, 60)
          : first,
      'rows seen after waiting': await da.countElementsOf<Visit>(),
    };
  }
  await da.changeDB(q['db'] ?? 'web_check');
  if (q['step'] == 'encrypt') {
    await da.encryptDatabase(q['newkey']!);
    return <String, Object?>{
      'encrypted': da.encryptionEnabled,
      'rows': await da.countElementsOf<Visit>(),
      'file': await disc.readFileAsString(fileName: 'f.txt'),
    };
  }
  await da.createTableIfNotExists(Visit());
  switch (q['step'] ?? 'all') {
    case 'write':
      final int n = int.tryParse(q['n'] ?? '') ?? 100;
      final int start = await da.countElementsOf<Visit>();
      for (int i = 0; i < n; i++) {
        await da.insertObjet(
          Visit('w${start + i}', 'S', false, DateTime(2026)),
        );
      }
      web.window.location.replace('about:blank');
      return <String, Object?>{'written': n};
    case 'durable':
      await da.insertObjet(
        Visit(
          'd${DateTime.now().microsecondsSinceEpoch}',
          'S',
          true,
          DateTime(2026),
        ),
      );
      final int seen = await da.countElementsOf<Visit>();
      return <String, Object?>{
        'rows seen by b012_data': seen,
        'rows read straight from IndexedDB': await independentCount(
          q['db'] ?? 'web_check',
        ),
      };
    case 'count':
      return <String, Object?>{'rows': await da.countElementsOf<Visit>()};
    case 'seed':
      await da.insertObjet(Visit('s1', 'Kaolack', true, DateTime(2026)));
      await disc.saveDataToDisc(
        'note confidentielle',
        DataType.text,
        takeThisName: 'f.txt',
      );
      return <String, Object?>{
        'rows': await da.countElementsOf<Visit>(),
        'encrypted': da.encryptionEnabled,
      };
    case 'read':
      return <String, Object?>{
        'rows': await da.countElementsOf<Visit>(),
        'file': await disc.readFileAsString(fileName: 'f.txt'),
      };
    case 'probe':
      return <String, Object?>{
        'probe': await attempt(() => da.countElementsOf<Visit>()),
      };
    case 'hold':
      await da.countElementsOf<Visit>();
      return <String, Object?>{'holding': true};
    default:
      return all();
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: Scaffold(body: Report())));
}

class Report extends StatefulWidget {
  const Report({super.key});

  @override
  State<Report> createState() => _ReportState();
}

class _ReportState extends State<Report> {
  String text = 'running';

  @override
  void initState() {
    super.initState();
    run(Uri.base.queryParameters)
        .then(
          (Map<String, Object?> r) => r,
          onError: (Object e) => <String, Object?>{'error': e.toString()},
        )
        .then((Map<String, Object?> r) {
          // ignore: avoid_print
          print('B012_WEB_CHECK ${jsonEncode(r)}');
          setState(() => text = const JsonEncoder.withIndent('  ').convert(r));
        });
  }

  @override
  Widget build(BuildContext context) =>
      SingleChildScrollView(child: Text(text));
}
