import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:b012_data/b012_disc_data.dart';
import 'package:b012_data/b012_sqlflite_easy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/harness.dart';

final DiscData disc = DiscData.instance;

void main() {
  late Sandbox sandbox;
  setUp(() async {
    sandbox = await Sandbox.create();
    disc.debugResetPaths();
  });
  tearDown(() async {
    await DataAccess.instance.closeDB();
    await sandbox.dispose();
    disc.debugResetPaths();
  });

  String legacyFiles() => sandbox.path(Platform.isWindows ? '.files' : 'files');

  test('a new installation saves its files in the support folder', () async {
    expect(await disc.filesPath, sandbox.path(p.join('Support', 'files')));
    expect(
      await disc.saveDataToDisc(
        'bonjour',
        DataType.text,
        takeThisName: 'a.txt',
      ),
      'a.txt',
    );
    expect(
      File(
        sandbox.path(p.join('Support', 'files', 'a.txt')),
      ).readAsStringSync(),
      'bonjour',
    );
    expect(await disc.readFileAsString(fileName: 'a.txt'), 'bonjour');
  });

  test(
    'overwriting a file replaces it whole and leaves no temporary file',
    () async {
      await disc.saveDataToDisc(
        'ancien contenu',
        DataType.text,
        takeThisName: 'b.txt',
      );
      await disc.saveDataToDisc(
        base64Encode(<int>[1, 2, 3]),
        DataType.base64,
        takeThisName: 'b.txt',
      );
      expect(await disc.readFileAsBytes(fileName: 'b.txt'), <int>[1, 2, 3]);
      final List<String> names = Directory(
        await disc.filesPath,
      ).listSync().map((FileSystemEntity e) => p.basename(e.path)).toList();
      expect(names, <String>['b.txt']);
    },
  );

  test('a file name never leaves the files folder', () async {
    for (final String name in <String>['../x.txt', 'a/../../x.txt']) {
      await expectLater(
        disc.saveDataToDisc('x', DataType.text, takeThisName: name),
        throwsArgumentError,
      );
      await expectLater(
        disc.readFileAsString(fileName: name),
        throwsArgumentError,
      );
    }
    expect(
      File(sandbox.path(p.join('Support', 'x.txt'))).existsSync(),
      isFalse,
    );
    expect(File(sandbox.path('x.txt')).existsSync(), isFalse);
  });

  test('files saved by 2.0.3 stay readable by name', () async {
    Directory(legacyFiles()).createSync(recursive: true);
    File(p.join(legacyFiles(), 'old.txt')).writeAsStringSync('hérité');
    expect(await disc.checkFileExists(fileName: 'old.txt'), isTrue);
    expect(await disc.readFileAsString(fileName: 'old.txt'), 'hérité');
    expect(
      await disc.readFileAsBase64(fileName: 'old.txt'),
      base64Encode(utf8.encode('hérité')),
    );
    expect(
      (await disc.getFile(fileName: 'old.txt'))?.path,
      p.join(legacyFiles(), 'old.txt'),
    );
  });

  test(
    'an application that kept its 2.0.3 base keeps its 2.0.3 folder',
    () async {
      final Directory record = Directory(
        sandbox.path(p.join('Support', 'databases')),
      )..createSync(recursive: true);
      File(p.join(record.path, 'locations.json')).writeAsStringSync(
        '{"sqlf_easy.db": "${sandbox.path('x.db').replaceAll(r'\', r'\\')}"}',
      );
      expect(await disc.filesPath, legacyFiles());
    },
  );

  test('append, delete, explicit absolute path', () async {
    await disc.saveDataToDisc('ab', DataType.text, takeThisName: 'c.txt');
    await disc.appendDataToFile('cd', DataType.text, fileName: 'c.txt');
    await disc.appendDataToFile(
      Uint8List.fromList(utf8.encode('ef')),
      DataType.bytes,
      fileName: 'c.txt',
    );
    expect(await disc.readFileAsString(fileName: 'c.txt'), 'abcdef');
    expect(await disc.deleteFile(fileName: 'c.txt'), isTrue);
    expect(await disc.checkFileExists(fileName: 'c.txt'), isFalse);
    expect(await disc.deleteFile(fileName: 'c.txt'), isTrue);

    final String explicit = sandbox.path(p.join('ailleurs', 'd.txt'));
    expect(
      await disc.saveDataToDisc(
        'ici',
        DataType.text,
        path: explicit,
        recursive: true,
      ),
      'd.txt',
    );
    expect(await disc.readFileAsString(path: explicit), 'ici');
  });

  test('nothing to save: null, empty text or empty list', () async {
    expect(await disc.saveDataToDisc(null, DataType.text), isNull);
    expect(await disc.saveDataToDisc('', DataType.text), isNull);
    expect(await disc.saveDataToDisc(Uint8List(0), DataType.bytes), isNull);
    expect(await disc.readFileAsString(fileName: 'absent.txt'), isNull);
  });
}
